param([Parameter(Mandatory=$true)][string]$SettingsPath,[Parameter(Mandatory=$true)][string]$StatusPath,[Parameter(Mandatory=$true)][string]$StopPath,[switch]$Live)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hpe-Redfish.ps1')
. (Join-Path $PSScriptRoot 'Redfish-Control.ps1')
Add-Type -AssemblyName System.Security
$config=Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
$origin=[Uri]('https://'+$config.IdracHost+'/');$watch=[Diagnostics.Stopwatch]::StartNew()
$headers=@{};$identity=$null;$mutex=$null;$owned=$false;$restoring=$false;$pending=$null;$failure=$false;$physicalMutex=$null;$physicalOwned=$false
$recoveryPath=Join-Path (Split-Path $SettingsPath) 'Cooling-Recovery.json'
function Write-Status([string]$State,[string]$Message,$Telemetry=$null) {
    $data=@{Time=(Get-Date -Format o);State=$State;Message=$Message;Live=[bool]$Live;Smart=$false;Fan=-1;Ipmi=$Telemetry;Gpu=$null;ManagementProvider='Redfish';TargetIdentity=$identity;IdracHost=$config.IdracHost;ProfileName=$config.ProfileName;CooldownRemaining=0;UptimeSeconds=[int]$watch.Elapsed.TotalSeconds}
    [IO.File]::WriteAllText($StatusPath+'.tmp',($data | ConvertTo-Json -Depth 12 -Compress));Move-Item -LiteralPath ($StatusPath+'.tmp') -Destination $StatusPath -Force
}
function Resource-Uri([string]$Path) {
    $url=[Uri]::new($origin,$Path)
    if ($url.Scheme -ne 'https' -or $url.Host -ne $origin.Host -or $url.Port -ne $origin.Port -or -not $url.AbsolutePath.StartsWith('/redfish/v1/')) {throw 'Untrusted Redfish resource link'}
    return $url.AbsoluteUri
}
function Get-Resource([string]$Path) {
    if (-not $restoring -and (Test-Path -LiteralPath $StopPath)) {throw 'Stop requested'}
    $response=Invoke-WebRequest -Uri (Resource-Uri $Path) -Headers $headers -Method Get -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 0
    return ($response.Content | ConvertFrom-Json)
}
function Set-NativeValues($Record,$Values) {
    if($Record.Serial -and [string](Get-Resource $systemPath).SerialNumber -ne [string]$Record.Serial){throw "Hardware serial mismatch before cooling write"}
    $current=Get-Resource $Record.Path
    if($Record.Kind -eq 'DellMinimum' -and -not $restoring){$null=Get-DellMinimumPlan $current $Values.'ThermalSettings.1.MinimumFanSpeed' $Record.Path}
    $requestHeaders=@{};foreach($key in $headers.Keys){$requestHeaders[$key]=$headers[$key]}
    if ($current.'@odata.etag') {$requestHeaders['If-Match']=[string]$current.'@odata.etag'}
    $body=Convert-NativePatch $Record.Kind $Values | ConvertTo-Json -Depth 6 -Compress
    $null=Invoke-WebRequest -Uri (Resource-Uri $Record.Path) -Headers $requestHeaders -Method Patch -ContentType 'application/json' -Body $body -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 0
    foreach($attempt in 1..6){if(Test-NativeValues $Record.Kind (Get-Resource $Record.Path) $Values){return};Start-Sleep -Seconds 2}
    throw 'Native cooling read-back did not match requested settings'
}
function Read-Telemetry($System,$Enclosure) {
    $thermal=$null;$power=$null
    if ($Enclosure.Thermal.'@odata.id') {$thermal=Get-Resource $Enclosure.Thermal.'@odata.id'}
    if ($Enclosure.Power.'@odata.id') {$power=Get-Resource $Enclosure.Power.'@odata.id'}
    if (-not $thermal -and $Enclosure.ThermalSubsystem.'@odata.id') {
        $sub=Get-Resource $Enclosure.ThermalSubsystem.'@odata.id';$temperatures=@();$fans=@()
        if ($sub.ThermalMetrics.'@odata.id') {$metrics=Get-Resource $sub.ThermalMetrics.'@odata.id';foreach($reading in @($metrics.TemperatureReadingsCelsius)){if($null -ne $reading){$temperatures+=@{Name=$reading.DeviceName;PhysicalContext=$reading.PhysicalContext;ReadingCelsius=$reading.Reading}}}}
        if ($sub.Fans.'@odata.id') {$collection=Get-Resource $sub.Fans.'@odata.id';if(@($collection.Members).Count -gt 32){throw 'Fan collection exceeds supported size'};foreach($member in $collection.Members){$fan=Get-Resource $member.'@odata.id';$reading=$fan.SpeedRPM.Reading;$units='RPM';if($null -eq $reading){$reading=$fan.SpeedPercent.Reading;$units='Percent'};$fans+=@{Name=$fan.Name;Reading=$reading;ReadingUnits=$units;Status=$fan.Status}}}
        $thermal=[pscustomobject]@{Temperatures=$temperatures;Fans=$fans;Status=$sub.Status}
        if(-not $power -and $null -ne $metrics.PowerWatts.Reading){$power=[pscustomobject]@{PowerControl=@(@{PowerConsumedWatts=$metrics.PowerWatts.Reading})}}
    }
    return Convert-HpeTelemetry $System $thermal $power
}
try {
    $sha=[Security.Cryptography.SHA256]::Create();try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($origin.Host.ToLowerInvariant()))).Replace('-','')}finally{$sha.Dispose()}
    $mutex=[Threading.Mutex]::new($false,('Global\ThermalOps-Redfish-'+$key));try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true};if(-not $owned){throw 'A Redfish worker already owns this target'}
    $password=[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($config.IdracPassProtected),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser));$headers.Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($config.IdracUser+':'+$password));$password=$null
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    Write-Status 'Starting' 'Discovering Redfish identity, telemetry and native cooling capabilities'
    $root=Get-Resource '/redfish/v1/';$systems=Get-Resource $root.Systems.'@odata.id';$chassis=Get-Resource $root.Chassis.'@odata.id'
    if(@($systems.Members).Count -ne 1 -or @($chassis.Members).Count -ne 1){throw 'Select an endpoint with one system and one chassis'}
    $systemPath=$systems.Members[0].'@odata.id';$chassisPath=$chassis.Members[0].'@odata.id';$system=Get-Resource $systemPath;$enclosure=Get-Resource $chassisPath
    $manufacturer=[string]$system.Manufacturer
    if($config.ManagementProvider -eq 'DellRedfish' -and $manufacturer -notmatch '^(Dell|Dell Inc\.?|Dell EMC)$'){throw 'Dell identity mismatch'}
    if($config.ManagementProvider -eq 'HPE' -and $manufacturer -notmatch 'HPE|Hewlett|HP\b'){throw 'HPE identity mismatch'}
    if($config.ManagementProvider -eq 'Supermicro' -and $manufacturer -notmatch 'Supermicro'){throw 'Supermicro identity mismatch'}
    $identity=@{Manufacturer=$manufacturer;Model=[string]$system.Model;Source='Redfish';CoolingProfile='BMC automatic / monitor only'}
    $identity.FirmwareRevision='Unknown';$identity.FirmwareSource='Redfish Manager';$identity.IdracGeneration='Unknown'
    if($manufacturer -match '^Dell' -and $root.Managers.'@odata.id'){
        try{
            $managers=Get-Resource $root.Managers.'@odata.id'
            if(@($managers.Members).Count -gt 16){throw 'Too many managers'}
            $bmc=@(foreach($member in $managers.Members){$candidate=Get-Resource $member.'@odata.id';if($candidate.ManagerType -eq 'BMC'){$candidate}})
            if($bmc.Count -eq 1){$identity.FirmwareRevision=[string]$bmc[0].FirmwareVersion;$identity.IdracGeneration=[string]$bmc[0].Model}
        }catch{}
    }
    if(-not $manufacturer -or -not $system.Model){throw 'Hardware identity unavailable'}
    if($Live -or (Test-Path -LiteralPath $recoveryPath)){
        if(-not $system.SerialNumber -or [string]$system.SerialNumber -match '^(Unknown|None|Default|To be filled)'){throw 'A usable hardware serial is required for cooling writes'}
        $hash=[Security.Cryptography.SHA256]::Create();try{$physicalKey=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(([string]$system.SerialNumber).Trim().ToUpperInvariant())))).Replace('-','')}finally{$hash.Dispose()}
        $physicalMutex=[Threading.Mutex]::new($false,('Global\R730FanPhysical_'+$physicalKey));try{$physicalOwned=$physicalMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$physicalOwned=$true};if(-not $physicalOwned){throw 'Another controller already owns this physical system'}
    }
    $thermalPath=[string]$enclosure.Thermal.'@odata.id';$subPath=[string]$enclosure.ThermalSubsystem.'@odata.id';$modePath=''
    $thermal=$null;$sub=$null;$mode=$null
    if($thermalPath){$thermal=Get-Resource $thermalPath};if($subPath){$sub=Get-Resource $subPath}
    if($manufacturer -match 'Supermicro' -and $root.Managers.'@odata.id'){$managers=Get-Resource $root.Managers.'@odata.id';if(@($managers.Members).Count -eq 1){$manager=Get-Resource $managers.Members[0].'@odata.id';$modePath=[string]$manager.Oem.Supermicro.FanMode.'@odata.id';if(-not $modePath){$modePath=([string]$managers.Members[0].'@odata.id').TrimEnd('/')+'/Oem/Supermicro/FanMode'};try{$mode=Get-Resource $modePath}catch{$modePath=''}}}
    $dellAttributes=$null;$dellPath=''
    if($manufacturer -match '^(Dell|Dell Inc\.?|Dell EMC)$'){
        try{$dellPath='/redfish/v1/Managers/System.Embedded.1/Attributes';$dellAttributes=Get-Resource $dellPath}catch{$dellPath=''}
    }
    $identity.NativeMinimumAvailable=$false
    if($dellAttributes){
        $identity.NativeMinimum=$dellAttributes.Attributes.'ThermalSettings.1.MinimumFanSpeed'
        $identity.NativeMinimumLimit=$dellAttributes.Attributes.'ThermalSettings.1.MFSMinimumLimit'
        $identity.NativeMaximumLimit=$dellAttributes.Attributes.'ThermalSettings.1.MFSMaximumLimit'
        try{$null=Get-DellMinimumPlan $dellAttributes 100 $dellPath;$identity.NativeMinimumAvailable=$true}catch{
            try{$null=Get-DellMinimumPlan $dellAttributes $identity.NativeMaximumLimit $dellPath;$identity.NativeMinimumAvailable=$true}catch{}
        }
    }
    $available=@();if($identity.NativeMinimumAvailable){$available+='Dell minimum fan floor (automatic cooling retained)'};if($thermal.Oem.Hpe.ThermalConfiguration){$available+='HPE thermal profile';if($null -ne $thermal.Oem.Hpe.FanPercentMinimum){$available+='HPE minimum fan %'}};if($mode.Mode){$available+='Supermicro fan mode'};if($sub.FansFullSpeedOverrideEnable -is [bool]){$available+='Redfish full-speed override'}
    $capabilities=if($available.Count){$available -join ', '}else{'No supported write capability detected'}
    $identity.Capabilities=$capabilities
    # Pending recovery is checked before any new writes or monitoring session.
    if(Test-Path -LiteralPath $recoveryPath){
        $record=Get-Content -LiteralPath $recoveryPath -Raw | ConvertFrom-Json
        if($record.Host -ne $origin.Host -or -not $system.SerialNumber -or $record.Serial -ne [string]$system.SerialNumber){throw 'Pending recovery target does not match hardware identity'}
        $expected=switch($record.Kind){HPE {$thermalPath};Supermicro {$modePath};RedfishOverride {$subPath};DellMinimum {$dellPath};default {''}}
        if(-not $expected -or $record.Path -ne $expected){throw 'Pending recovery resource mismatch'}
        $pending=$record;$restoring=$true;Set-NativeValues $record $record.Before;Remove-Item -LiteralPath $recoveryPath;$pending=$null;$restoring=$false
    }
    $telemetry=Read-Telemetry $system $enclosure
    if($Live){
        if(-not $system.SerialNumber -or $telemetry.ReportedHealth -ne 'TELEMETRY OK'){throw 'Native control requires serial identity and healthy complete temperature/fan telemetry'}
        if($config.ManagementProvider -eq 'DellRedfish'){
            if($config.NativeCoolingProfile -ne 'DellMinimum' -or -not $config.NativeMinimumEnabled){throw 'Enable Dell minimum fan percentage on Connection before applying'}
            $plan=Get-DellMinimumPlan $dellAttributes $config.NativeMinimum $dellPath
        }else{$plan=Get-NativeCoolingPlan $config $manufacturer $thermal $sub $mode $thermalPath $subPath $modePath}
        $pending=@{Host=$origin.Host;Serial=[string]$system.SerialNumber;Kind=$plan.Kind;Path=$plan.Path;Before=$plan.Before;After=$plan.After}
        $pending | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recoveryPath -Encoding UTF8
        Set-NativeValues $pending $pending.After;$identity.CoolingProfile='Native cooling / '+$config.NativeCoolingProfile
    }
    while(-not (Test-Path -LiteralPath $StopPath)){
        $system=Get-Resource $systemPath;$enclosure=Get-Resource $chassisPath
        if($pending -and [string]$system.SerialNumber -ne $pending.Serial){throw 'Hardware identity changed'}
        $telemetry=Read-Telemetry $system $enclosure
        if($Live -and $telemetry.ReportedHealth -ne 'TELEMETRY OK'){throw 'Thermal telemetry requires attention; restoring native settings'}
        Write-Status $(if($Live){'NATIVE COOLING'}else{'MONITORING'}) ($capabilities+' | hardware verification pending') $telemetry
        foreach($tick in 1..20){if(Test-Path -LiteralPath $StopPath){break};Start-Sleep -Milliseconds 500}
    }
}catch{$failure=$true;Write-Status 'FAULT' ('Redfish operation failed: '+$_.Exception.Message)}
finally {
    if($pending){
        $restoring=$true;Write-Status 'Restoring' 'Restoring original native cooling settings';$restored=$false
        foreach($attempt in 1..3){try{Set-NativeValues $pending $pending.Before;Remove-Item -LiteralPath $recoveryPath -ErrorAction Stop;$restored=$true;break}catch{Start-Sleep -Seconds 1}}
        if($restored){Write-Status 'Stopped' 'Original native cooling settings verified'}else{Write-Status 'RESTORE FAILED' 'Native cooling restore unconfirmed; check BMC and retained recovery record'}
    }elseif(-not $failure -or (Test-Path -LiteralPath $StopPath)){Write-Status 'Stopped' 'Read-only monitor stopped'}
    $headers.Clear();if($physicalOwned){$physicalMutex.ReleaseMutex()};if($physicalMutex){$physicalMutex.Dispose()};if($owned){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}
}
