param([Parameter(Mandatory=$true)][string]$TestDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$msi=Join-Path $root 'Dist\Thermal-Ops-MSI-Test-1.4.1.msi'
if(-not(Test-Path -LiteralPath $msi)){throw 'Build-Msi.ps1 -Smoke must run first'}
if(Test-Path -LiteralPath $TestDirectory){throw 'Use a new, empty test directory'}
New-Item -ItemType Directory -Path $TestDirectory|Out-Null
$target=Join-Path $TestDirectory 'Application'
function Run-Msi([string]$Arguments,[string]$Log){
    $process=Start-Process msiexec.exe -ArgumentList ($Arguments+' /qn /norestart /L*v "'+$Log+'"') -Wait -PassThru -WindowStyle Hidden
    if($process.ExitCode -ne 0){throw ('MSI test failed with code '+$process.ExitCode+'; see '+$Log)}
}
$installed=$false
try{
    Run-Msi ('/i "'+$msi+'" INSTALLFOLDER="'+$target+'"') (Join-Path $TestDirectory 'install.log');$installed=$true
    $shell=New-Object -ComObject WScript.Shell
    $links=@((Join-Path ([Environment]::GetFolderPath('Startup')) 'Thermal Ops MSI Packaging Test.lnk'),(Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Thermal Ops MSI Packaging Test.lnk'))
    foreach($link in $links){
        if(-not(Test-Path -LiteralPath $link)){throw 'Optional shortcut missing'}
        $shortcut=$shell.CreateShortcut($link)
        if($shortcut.TargetPath -ne (Join-Path $target 'ThermalOps.exe')){throw 'Shortcut points outside test installation'}
    }
    if($shell.CreateShortcut($links[0]).Arguments -ne '--startup'){throw 'Startup arguments missing'}
    $payload=Join-Path $PSScriptRoot 'Payload';$count=0
    foreach($file in Get-ChildItem $payload -File -Recurse){
        $relative=$file.FullName.Substring($payload.Length+1)
        if($relative -match '(^|\\)(Profiles|Runs|MsiBuild)(\\|$)|(^|\\)[^\\]*-test\.txt$|\.jsonl$|(^|\\)(preview|.*-preview)\.png$|\.bak$'){continue}
        $installedName=if($relative -eq 'settings.json'){'settings.default.json'}else{$relative}
        $copy=Join-Path $target $installedName
        if(-not(Test-Path -LiteralPath $copy) -or (Get-FileHash $copy).Hash -ne (Get-FileHash $file.FullName).Hash){throw ('Installed payload differs: '+$relative)}
        $count++
    }
    $settings=Join-Path $target 'settings.json'
    $factory=Get-Content $settings -Raw|ConvertFrom-Json
    if($factory.IdracPassProtected -or $factory.GpuSourceConfirmed){throw 'Private or configured settings were installed'}
    $marker='{"ProfileName":"MSI retention test","SmokeMarker":"preserve"}'
    [IO.File]::WriteAllText($settings,$marker)
    $profiles=Join-Path $target 'Profiles';New-Item -ItemType Directory -Path $profiles|Out-Null
    [IO.File]::WriteAllText((Join-Path $profiles 'retention.txt'),'preserve')
    Run-Msi ('/fa "'+$msi+'"') (Join-Path $TestDirectory 'repair.log')
    if([IO.File]::ReadAllText($settings) -ne $marker){throw 'Repair overwrote settings'}
    Run-Msi ('/x "'+$msi+'"') (Join-Path $TestDirectory 'uninstall.log');$installed=$false
    if(Test-Path (Join-Path $target 'ThermalOps.exe')){throw 'Uninstall left installed executable'}
    foreach($link in $links){if(Test-Path -LiteralPath $link){throw 'Uninstall left test shortcut'}}
    if([IO.File]::ReadAllText($settings) -ne $marker -or -not(Test-Path (Join-Path $profiles 'retention.txt'))){throw 'Uninstall removed user data'}
    "PASS: $count installed payload hashes, factory settings, repair retention and uninstall retention. No app or cooling worker launched."
}finally{
    if($installed){Run-Msi ('/x "'+$msi+'"') (Join-Path $TestDirectory 'cleanup.log')}
}
