param([string]$InnoCompiler)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot)
try {
    $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $sources=@('R730FanControl','ServerProfiles','TemperatureTrends','FleetOverview','FeedDiscovery','CoolingShutdownDialog','ThermalBrand','LocalSetupDialog','BundledTools','HardwareSupportReport','AppUpdates') | ForEach-Object {'.\R730-App-Fleet\'+$_+'.cs'}
    & $compiler /nologo /target:winexe /out:Installer\Payload\ThermalOps.exe /win32icon:R730-App-Fleet\Assets\ThermalOps.ico /resource:R730-App-Fleet\Assets\ThermalOps.ico,ThermalOps.ico /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll /reference:System.Security.dll /reference:System.Management.dll $sources
    if($LASTEXITCODE){throw 'Dashboard compilation failed'}
    & $compiler /nologo /target:winexe /main:UpdateLauncher /out:Installer\Payload\ThermalOpsUpdater.exe /reference:System.Windows.Forms.dll /reference:System.Management.dll .\Installer\UpdateLauncher.cs .\Installer\MsiActions.cs
    if($LASTEXITCODE){throw 'Updater compilation failed'}
    & $compiler /nologo /target:exe /out:Installer\Payload\LocalHardware\LocalWorker.exe /reference:Installer\Payload\LocalHardware\LibreHardwareMonitorLib.dll /reference:System.Core.dll /reference:System.Web.Extensions.dll .\R730-App-Fleet\LocalWorker.cs
    if($LASTEXITCODE){throw 'Local worker compilation failed'}
    foreach($file in @('Controller.ps1','R730-SmartControl.ps1','GpuProviders.ps1','SystemIdentity.ps1','DellCompatibility.ps1','RedfishWorker.ps1','Redfish-Control.ps1','Hpe-Redfish.ps1','HARDWARE-SUPPORT.md','HPE-SUPPORT.md','IDRAC-COMPATIBILITY.md','README.md')){Copy-Item -LiteralPath (Join-Path '.\R730-App-Fleet' $file) -Destination .\Installer\Payload -Force}
    Copy-Item -LiteralPath .\Installer\Import-Profiles.ps1 -Destination .\Installer\Payload -Force
    if (-not $InnoCompiler) { $InnoCompiler=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe' }; if (-not (Test-Path -LiteralPath $InnoCompiler)) { throw 'Install Inno Setup 6 or supply -InnoCompiler with its ISCC.exe path' }; & $InnoCompiler /Q .\Installer\ThermalOps.iss
    if($LASTEXITCODE){throw 'Setup compilation failed'}
} finally {Pop-Location}
