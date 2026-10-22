$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\R730-App-Fleet\SystemIdentity.ps1')
. (Join-Path $PSScriptRoot '..\R730-App-Fleet\DellCompatibility.ps1')
. (Join-Path $PSScriptRoot '..\R730-App-Fleet\Hpe-Redfish.ps1')
. (Join-Path $PSScriptRoot '..\R730-App-Fleet\Redfish-Control.ps1')
$script:checks=0
function Assert($Test,[string]$Message){if(-not $Test){throw $Message};$script:checks++}
function Reject([scriptblock]$Code,[string]$Message){$failed=$false;try{& $Code|Out-Null}catch{$failed=$true};Assert $failed $Message}
$mc="Firmware Revision : 2.86`nManufacturer ID : 674`nProduct ID : 256`nAux Firmware Rev Info :`n 0x00`n 0x06`n 0x56`n 0x56"
$identity=Convert-TargetIdentity "Product Manufacturer : Dell Inc.`nProduct Name : PowerEdge R730"
Assert (Get-DellCompatibility $identity $mc).ManualControlAllowed 'Recorded R730 fingerprint rejected'
foreach($model in @('R710','R720','R730xd','R630','R740','R750','R760','R770','Unknown')){
    $identity.Model='PowerEdge '+$model
    Assert (-not (Get-DellCompatibility $identity $mc).ManualControlAllowed) ('Unverified model enabled raw writes: '+$model)
}
$identity.Model='PowerEdge R730'
foreach($changed in @('',$mc.Replace('2.86','2.87'),$mc.Replace('674','999'),$mc.Replace('256','257'),$mc.Replace('0x56','0x57'))){Assert (-not (Get-DellCompatibility $identity $changed).ManualControlAllowed) 'Unverified firmware/controller enabled writes'}
$identity.Manufacturer='Not Dell';Assert (-not (Get-DellCompatibility $identity $mc).ManualControlAllowed) 'Vendor mismatch accepted'
$fru="FRU Device Description : Add-on (ID 1)`n Product Manufacturer : Dell Inc.`n Product Name : PowerEdge R730"
Assert ((Convert-TargetIdentity $fru).Model -eq 'Unknown model') 'Non-system FRU used for identity'
$sensor="CPU1 Temp | 41 | degrees C | ok`nInlet Temp | 22 | degrees C | ok`nFan1 | 3000 | RPM | ok`nSystem Power | 250 | Watts | ok"
$t=Convert-DellMonitorTelemetry $sensor
Assert ($t.CpuMax -eq 41 -and $t.Fans.Count -eq 1 -and $t.Watts -eq 250 -and $null -eq $t.Exhaust -and $t.ReportedHealth -eq 'TELEMETRY OK') 'Generic telemetry incorrectly requires R730 sensor inventory'
Assert ((Convert-DellMonitorTelemetry ($sensor+"`nSystem Power | 250 | Watts | ok")).Watts -eq $null) 'Overlapping whole-server power counted'
Assert ((Convert-DellMonitorTelemetry $sensor.Replace('3000','na')).ReportedHealth -eq 'DEGRADED') 'Missing sensor shown healthy'
Assert ((Convert-DellMonitorTelemetry $sensor.Replace('RPM | ok','RPM | cr')).ReportedHealth -eq 'ATTENTION') 'Fault status lost'
Assert ((Convert-DellMonitorTelemetry 'CPU Temp | 95 | degrees C | ok | na | na | na | 90 | 100 | 110').ReportedHealth -eq 'ATTENTION') 'Advertised threshold ignored'
Assert ((Convert-DellMonitorTelemetry '').ReportedHealth -eq 'UNKNOWN') 'Empty telemetry shown healthy'
$attrs=[pscustomobject]@{'@odata.type'='#DellAttributes.v1_0_0.DellAttributes';Attributes=@{'ThermalSettings.1.MinimumFanSpeed'=255;'ThermalSettings.1.MFSMinimumLimit'=20;'ThermalSettings.1.MFSMaximumLimit'=100}}
$path='/redfish/v1/Managers/System.Embedded.1/Attributes'
$plan=Get-DellMinimumPlan $attrs 60 $path
Assert ($plan.Before.'ThermalSettings.1.MinimumFanSpeed' -eq 255 -and $plan.After.'ThermalSettings.1.MinimumFanSpeed' -eq 60) 'Dell original sentinel not preserved'
Assert ((Convert-NativePatch $plan.Kind $plan.After).Attributes.'ThermalSettings.1.MinimumFanSpeed' -eq 60) 'Incorrect Dell patch envelope'
Assert (Test-NativeValues DellMinimum $attrs $plan.Before) 'Dell original read-back failed'
Reject {Get-DellMinimumPlan $attrs 10 $path} 'Below-firmware floor accepted'
Reject {Get-DellMinimumPlan $attrs 101 $path} 'Above-firmware ceiling accepted'
Reject {Get-DellMinimumPlan $attrs 60.5 $path} 'Fractional fan minimum accepted'
$attrs.Attributes.'ThermalSettings.1.MinimumFanSpeed'=80
Reject {Get-DellMinimumPlan $attrs 60 $path} 'Existing fan floor lowered'
Reject {Get-DellMinimumPlan $attrs 100 '/redfish/v1/other'} 'Wrong attribute path accepted'
Reject {Convert-NativePatch DellMinimum @{'ThermalSettings.1.ThermalProfile'='Minimum Power'}} 'Arbitrary Dell settings accepted'
Reject {Convert-NativePatch DellMinimum @{'ThermalSettings.1.MinimumFanSpeed'=$true}} 'Boolean accepted as minimum'
$attrs.Attributes.'ThermalSettings.1.MFSMinimumLimit'=255
Reject {Get-DellMinimumPlan $attrs 100 $path} 'Unknown firmware limit accepted'

# Actual worker with a fake executable transport. Raw attempts are logged and fail.
# No network connections or physical cooling changes are made.
$fixture=Join-Path $PSScriptRoot ('RedfishTest-Dell-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$fake=Join-Path $fixture 'ipmi-fixture.exe'
Add-Type -TypeDefinition @'
using System; using System.IO;
public class FakeIpmi {
 public static void Main(string[] args){
  string root=AppDomain.CurrentDomain.BaseDirectory;
  string request=String.Join(" ",args);
  if(Array.IndexOf(args,"raw")>=0){File.AppendAllText(Path.Combine(root,"raw-attempt.txt"),"raw");Environment.Exit(77);}
  if(request.EndsWith("fru print"))Console.WriteLine("Product Manufacturer : Dell Inc.\nProduct Name : PowerEdge R740\nProduct Serial : FIXTURE");
  else if(request.EndsWith("mc info"))Console.WriteLine("Firmware Revision : 7.00\nManufacturer ID : 674\nProduct ID : 256");
  else if(request.EndsWith("sensor"))Console.WriteLine("CPU1 Temp | 41 | degrees C | ok\nFan1 | 3000 | RPM | ok\nSystem Power | 250 | Watts | ok");
  else Environment.Exit(78);
 }
}
'@ -OutputAssembly $fake -OutputType ConsoleApplication
Add-Type -AssemblyName System.Security
$password=[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes('fixture-only'),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
$settings=Join-Path $fixture 'settings.json';$status=Join-Path $fixture 'status.json'
@{IpmiExe=$fake;UseBundledIpmi=$false;IdracHost='fixture.invalid';IdracUser='fixture';IdracPassProtected=$password;GpuMode='Unconfigured';GpuSourceConfirmed=$false}|ConvertTo-Json|Set-Content $settings
& (Join-Path $PSScriptRoot '..\R730-App-Fleet\Controller.ps1') -Live -SettingsPath $settings -StatusPath $status -Iterations 1
$final=Get-Content $status -Raw|ConvertFrom-Json
Assert (-not $final.Live -and $final.State -eq 'Stopped' -and $final.TargetIdentity.Model -eq 'PowerEdge R740') 'Unsupported live request did not fall back to monitoring'
Assert (-not (Test-Path (Join-Path $fixture 'raw-attempt.txt'))) 'Unsupported worker attempted a raw write (including restoration)'
"PASS: $script:checks Dell compatibility, telemetry, native bounds and actual-worker no-write checks."
