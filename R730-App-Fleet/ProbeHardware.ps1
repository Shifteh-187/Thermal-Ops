param([Parameter(Mandatory=$true)][string]$SettingsPath,[Parameter(Mandatory=$true)][string]$OutputPath,[switch]$IncludeLocal,[switch]$LocalOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'HardwareDiscovery.ps1')
Add-Type -AssemblyName System.Security
$config=Get-Content -LiteralPath $SettingsPath -Raw|ConvertFrom-Json
$rows=New-Object Collections.Generic.List[object];$checks=New-Object Collections.Generic.List[object];$locators=@();$identity=@{Manufacturer='Not identified';Model='Not identified';Source='Read-only discovery'};$watch=[Diagnostics.Stopwatch]::StartNew();$privateValues=@([string]$config.IdracHost,[Environment]::MachineName);$password='';$phase='Starting';$done=$false
function Clean-Probe([object]$Value,[switch]$Firmware){$text=[string]$Value;foreach($secret in $script:privateValues){if($secret){$text=$text.Replace($secret,'[private identifier removed]')}};$text=[regex]::Replace($text,'(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}','[UUID removed]');if(-not $Firmware){$text=$text -replace '\b(?:\d{1,3}\.){3}\d{1,3}\b','[address removed]'};$text=$text -replace '[\r\n]',' ';if($text.Length -gt 180){$text=$text.Substring(0,180)};return $text}
function Save-Probe {
    $data=@{Time=(Get-Date -Format o);Phase=$phase;Complete=$done;Rows=@($rows.ToArray());Checks=@($checks.ToArray());HardwareDiscovery=@($locators);TargetIdentity=$identity}
    $json=$data|ConvertTo-Json -Depth 10 -Compress
    foreach($secret in $script:privateValues){if($secret){$encoded=($secret|ConvertTo-Json -Compress);$encoded=$encoded.Substring(1,$encoded.Length-2);$json=$json.Replace($encoded,'[private identifier removed]')}}
    [IO.File]::WriteAllText($OutputPath+'.tmp',$json);Move-Item -LiteralPath ($OutputPath+'.tmp') -Destination $OutputPath -Force
}
function Row([string]$Backend,[string]$Kind,$Name,$Identifier,$Value,$Units,[string]$Access='Read only'){
    if($rows.Count -lt 512){$rows.Add(@{Backend=$Backend;Kind=$Kind;Name=(Clean-Probe $Name);Identifier=(Clean-Probe $Identifier);Value=(Clean-Probe $Value -Firmware:($Kind -eq 'Identity' -and [string]$Name -match '^Firmware'));Units=(Clean-Probe $Units);Access=$Access})}
}
function Query([string]$Backend,[string]$Name,[scriptblock]$Action){
    if($watch.Elapsed.TotalSeconds -gt 100){$checks.Add(@{Backend=$Backend;Query=$Name;Result='Skipped: scan time budget reached'});return}
    $script:phase=$Backend+' / '+$Name;Save-Probe
    try{& $Action;$checks.Add(@{Backend=$Backend;Query=$Name;Result='Read completed'})}catch{$checks.Add(@{Backend=$Backend;Query=$Name;Result='Unavailable: permissions, authentication, transport or unsupported resource; no write attempted'})};Save-Probe
}
function Ipmi-Read([string[]]$Arguments){
    # Only callers below supply fixed read commands. Password is passed through the child environment.
    $tool=if($config.UseBundledIpmi -ne $false -or $config.IpmiExe -eq 'Bundled'){Join-Path $PSScriptRoot 'Tools\IPMI\ipmitool.exe'}else{[string]$config.IpmiExe}
    $tokens=@('-I','lanplus','-H',[string]$config.IdracHost,'-U',[string]$config.IdracUser,'-E')+$Arguments
    foreach($token in $tokens){if($token -match '["\r\n]'){throw 'Invalid connection token'}}
    $p=New-Object Diagnostics.Process;$p.StartInfo=New-Object Diagnostics.ProcessStartInfo;$p.StartInfo.FileName=$tool;$p.StartInfo.Arguments=($tokens|ForEach-Object{'"'+$_+'"'}) -join ' ';$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true;$p.StartInfo.EnvironmentVariables['IPMI_PASSWORD']=$password
    try{$null=$p.Start();$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(12000)){$p.Kill();$p.WaitForExit();throw 'Read query timeout'};$text=$out.GetAwaiter().GetResult();$null=$err.GetAwaiter().GetResult();if($p.ExitCode -ne 0){throw 'Read query failed'};if($text.Length -gt 1048576){throw 'Inventory too large'};return $text}finally{$p.Dispose()}
}
try{
    if($config.ManagementProvider -ne 'Local' -and -not $LocalOnly){
        try{$bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($config.IdracPassProtected),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser);$password=[Text.Encoding]::UTF8.GetString($bytes);[Array]::Clear($bytes,0,$bytes.Length)}catch{$checks.Add(@{Backend='Credentials';Query='Saved login';Result='Credentials unavailable for this Windows user'})}
        Query IPMI 'Controller identity' {$raw=Ipmi-Read @('mc','info');foreach($line in $raw -split '\r?\n'){if($line -match '^\s*(Firmware Revision|Manufacturer ID|Product ID)\s*:\s*(.*)$'){Row IPMI Identity $Matches[1] '' $Matches[2] ''}}}
        Query IPMI 'System model' {$raw=Ipmi-Read @('fru','print');foreach($line in $raw -split '\r?\n'){if($line -match '^\s*Product Serial\s*:\s*(.*)$'){$script:privateValues+= $Matches[1].Trim()};if($line -match '^\s*Product (Manufacturer|Name)\s*:\s*(.*)$'){Row IPMI Identity $Matches[1] '' $Matches[2] ''}}}
        Query IPMI 'SDR sensor identifiers' {$script:locators=@(Convert-SdrLocators (Ipmi-Read @('sdr','elist','all')));foreach($item in $locators){$item.Name=Clean-Probe $item.Name;Row IPMI 'Sensor locator' $item.Name ($item.SensorNumber+' / entity '+$item.EntityId) $item.Status ''}}
        Query IPMI 'Sensor readings' {$raw=Ipmi-Read @('sensor');foreach($line in $raw -split '\r?\n'){$p=@($line -split '\|');if($p.Count -ge 3){$kind=switch($p[2].Trim()){'RPM'{'Fan'};'degrees C'{'Temperature'};'Watts'{'Power'};default{'Sensor'}};Row IPMI $kind $p[0].Trim() '' $p[1].Trim() $p[2].Trim()}}}
        $origin=[Uri]('https://'+$config.IdracHost+'/');$headers=@{Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(([string]$config.IdracUser+':'+$password)))}
        $queue=New-Object Collections.Generic.List[string];foreach($path in @('/redfish/v1/','/redfish/v1/Systems','/redfish/v1/Chassis','/redfish/v1/Managers')){$queue.Add($path)};$seen=@{}
        for($n=0;$n -lt $queue.Count -and $n -lt 24 -and $watch.Elapsed.TotalSeconds -lt 100;$n++){
            $path=$queue[$n];if($seen[$path]){continue};$seen[$path]=$true
            Query Redfish ($(if($path.StartsWith('/redfish/v1/')){'GET '+(Clean-Probe $path)}else{'GET resource link'})) {
                $uri=[Uri]::new($origin,$path);if($uri.Scheme -ne 'https' -or $uri.Authority -ne $origin.Authority -or $uri.Query -or $uri.Fragment -or -not $uri.AbsolutePath.StartsWith('/redfish/v1/') -or $path -match '\.\.'){throw 'Untrusted resource'}
                $response=Invoke-WebRequest -Uri $uri.AbsoluteUri -Headers $headers -Method Get -UseBasicParsing -TimeoutSec 6 -MaximumRedirection 0
                if($response.Content.Length -gt 1048576){throw 'Inventory too large'};$data=$response.Content|ConvertFrom-Json
                if($data.SerialNumber){$script:privateValues += [string]$data.SerialNumber}
                Row Redfish Resource $data.Name $uri.AbsolutePath 'GET succeeded' ''
                $script:locators += @{Kind='Redfish GET';Path=(Clean-Probe $uri.AbsolutePath)}
                foreach($name in @('Manufacturer','Model','FirmwareVersion')){if($data.$name){Row Redfish Identity $name '' $data.$name ''}}
                foreach($group in @('Temperatures','Fans','PowerControl','TemperatureReadingsCelsius')){foreach($item in @($data.$group)){if($null -eq $item){continue};$reading=if($null -ne $item.ReadingCelsius){$item.ReadingCelsius}elseif($null -ne $item.Reading){$item.Reading}elseif($null -ne $item.PowerConsumedWatts){$item.PowerConsumedWatts}else{'Not reported'};$id=if($item.'@odata.id'){$item.'@odata.id'}else{$uri.AbsolutePath+'#'+$group+'/'+$item.MemberId};Row Redfish $group $item.Name $id $reading $item.ReadingUnits}}
                foreach($member in @($data.Members)){if($member.'@odata.id' -and $queue.Count -lt 64){$queue.Add([string]$member.'@odata.id')}}
                foreach($name in @('Thermal','Power','Sensors','ThermalSubsystem','ThermalMetrics','Fans','Processors','Memory')){if($data.$name.'@odata.id' -and $queue.Count -lt 64){$queue.Add([string]$data.$name.'@odata.id')}}
                if($data.ReadingType -or $null -ne $data.Reading){Row Redfish Sensor $data.Name $uri.AbsolutePath $data.Reading $data.ReadingUnits}
            }
        }
        $headers.Clear()
    }
    if($IncludeLocal -or $config.ManagementProvider -eq 'Local'){
        Query Windows 'Local hardware identity' {
            foreach($class in @('Win32_ComputerSystem','Win32_BaseBoard','Win32_Processor','Win32_VideoController')){foreach($item in @(Get-CimInstance $class -OperationTimeoutSec 4 -ErrorAction Stop)){$name=if($class -eq 'Win32_ComputerSystem'){$item.Model}else{$item.Name};if($item.SerialNumber){$script:privateValues += [string]$item.SerialNumber};$id='';if($item.PNPDeviceID -match 'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})'){$id='PCI VEN_'+$Matches[1]+'&DEV_'+$Matches[2]};Row Windows Device $name $id $item.Manufacturer $class}}
        }
        Query Local 'Driver-exposed sensors and channels' {
            $file=$OutputPath+'.local.json';$exe=Join-Path $PSScriptRoot 'LocalHardware\LocalWorker.exe';$p=Start-Process -FilePath $exe -ArgumentList ('--probe "'+$file+'"') -PassThru -WindowStyle Hidden
            try{if(-not $p.WaitForExit(45000)){$p.Kill();$p.WaitForExit();throw 'Local discovery timeout'};if(-not(Test-Path -LiteralPath $file)){throw 'Local driver unavailable or busy with active worker'};$data=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json;foreach($item in @($data.Sensors)){Row Local $item.Type $item.Name $item.Id $item.Value $item.Units $item.Access}}finally{$p.Dispose();if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
        }
    }
}catch{$checks.Add(@{Backend='Discovery';Query='Overall scan';Result='Scan incomplete; existing cooling workers were not stopped'})}
finally{$password=$null;$script:phase='Complete';$script:done=$true;Save-Probe}
