param([switch]$Custom)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. (Join-Path $root 'R730-App-Fleet\Controller.ps1') -LibraryOnly
foreach($message in @('Required R730 telemetry missing: two Temp CPUs, inlet and exhaust required','Command timed out after 12 seconds','External command failed (exit 1)')){if((Get-ControllerExitReason $message) -notin @('TelemetryUnavailable','ConnectionOrCommandFailure')){throw 'Transient failure classification rejected'}}
foreach($message in @('No RPM rise after substantial fan increase: Fan1','Fan1 missing or stalled','Sensor reports unhealthy status: Temp')){if((Get-ControllerExitReason $message) -ne 'HardwareSafetyFault'){throw 'Hardware fault classified as transient'}}
if((Get-ControllerExitReason 'Another controller instance is running for this iDRAC') -ne 'ConfigurationOrUnexpectedFault'){throw 'Ownership lock retry permitted'}
$locators=@(Convert-SdrLocators "Temp | 0Eh | ok | 3.1 | 40 degrees C`nTemp | 0Fh | ok | 3.2 | 41 degrees C`ninvalid | BAD | ok | 3.3 | na")
if($locators.Count -ne 2 -or $locators[0].SensorNumber -ne '0x0E' -or $locators[1].EntityId -ne '3.2'){throw 'SDR locator parsing failed'}
$fixture=Join-Path $PSScriptRoot ('MsiBuild\Recovery-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $fixture -Force|Out-Null
$fake=Join-Path $fixture 'fake-ipmi.exe'
Add-Type -TypeDefinition @'
using System;using System.IO;
class FakeRecoveryIpmi {
 public static void Main(string[] args){
  string dir=AppDomain.CurrentDomain.BaseDirectory,request=String.Join(" ",args),counter=Path.Combine(dir,"samples.txt");
  int n=File.Exists(counter)?int.Parse(File.ReadAllText(counter)):0;
  if(Array.IndexOf(args,"raw")>=0){File.AppendAllText(Path.Combine(dir,"raw.txt"),n+" "+request.Substring(request.IndexOf("raw"))+"\n");return;}
  if(request.EndsWith("fru print")){Console.WriteLine("Product Manufacturer : Dell Inc.\nProduct Name : PowerEdge R730\nProduct Serial : RECOVERY-FIXTURE");return;}
  if(request.EndsWith("mc info")){Console.WriteLine("Firmware Revision : 2.86\nManufacturer ID : 674\nProduct ID : 256\nAux Firmware Rev Info :\n 0x00\n 0x06\n 0x56\n 0x56");return;}
  if(request.EndsWith("sdr elist all")){Console.WriteLine("Temp | 0Eh | ok | 3.1 | 40 degrees C");return;}
  if(request.EndsWith("sensor")){
   n++;File.WriteAllText(counter,n.ToString());
   if(n>=4){Console.WriteLine("Inlet Temp | 23 | degrees C | ok");return;}
   Console.WriteLine("Temp | 40 | degrees C | ok\nTemp | 41 | degrees C | ok\nInlet Temp | 23 | degrees C | ok\nExhaust Temp | 30 | degrees C | ok");
   for(int i=1;i<=6;i++)Console.WriteLine("Fan"+i+" | 8400 | RPM | ok");return;
  }
  Environment.Exit(2);
 }
}
'@ -OutputAssembly $fake -OutputType ConsoleApplication
Add-Type -AssemblyName System.Security
$password=[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes('fixture'),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
$settings=Join-Path $fixture 'settings.json';$status=Join-Path $fixture 'status.json'
@{IpmiExe=$fake;UseBundledIpmi=$false;IdracHost='recovery-fixture.invalid';IdracUser='fixture';IdracPassProtected=$password;GpuMode='ServerOnly';GpuSourceConfirmed=$true}|ConvertTo-Json|Set-Content $settings
if($Custom){$customSettings=Get-Content $settings -Raw|ConvertFrom-Json;$customSettings|Add-Member FanCurveMode 'Custom';$customSettings|Add-Member FanCurves @(@{Source='CpuMax';Enabled=$true;Points=@(@{Temperature=0;Percent=80},@{Temperature=100;Percent=80})});$customSettings|ConvertTo-Json -Depth 8|Set-Content $settings}
$controller=Join-Path $root 'R730-App-Fleet\Controller.ps1'
$p=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$controller+'" -Live -SettingsPath "'+$settings+'" -StatusPath "'+$status+'" -Iterations 8') -Wait -PassThru -WindowStyle Hidden
if($p.ExitCode -eq 0){throw 'Missing telemetry did not fault'}
$final=Get-Content $status -Raw|ConvertFrom-Json
if($final.ExitReason -ne 'TelemetryUnavailable' -or -not $final.RetryAllowed -or $final.FailureMessage -notmatch 'Required R730 telemetry missing' -or $final.State -ne 'Stopped'){throw 'Original cause or restore result lost'}
$writes=Get-Content (Join-Path $fixture 'raw.txt')
if($Custom -and -not($writes|Where-Object{$_ -eq '3 raw 0x30 0x30 0x02 0xff 0x50'})){throw 'Custom curve demand did not reach validated shared output'};if(-not($writes|Where-Object{$_ -match '^3 raw 0x30 0x30 0x01 0x00$'})){throw 'Takeover did not wait for three complete samples'}
if(-not($writes|Where-Object{$_ -match 'raw 0x30 0x30 0x01 0x01$'})){throw 'Auto restoration not attempted'}
if(Test-Path (Join-Path $fixture 'Dell-Auto-Recovery.pending')){throw 'Successful restore left pending marker'}
if($final.HardwareDiscovery[0].SensorNumber -ne '0x0E'){throw 'Discovery absent from final snapshot'}
Remove-Item -LiteralPath (Join-Path $fixture 'raw.txt'),(Join-Path $fixture 'samples.txt')
$recovery=Join-Path $fixture 'Dell-Auto-Recovery.pending'
@{Host='wrong-target.invalid';Serial='wrong-serial'}|ConvertTo-Json|Set-Content $recovery
$p=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$controller+'" -Live -SettingsPath "'+$settings+'" -StatusPath "'+$status+'" -Iterations 3') -Wait -PassThru -WindowStyle Hidden
$final=Get-Content $status -Raw|ConvertFrom-Json
if($p.ExitCode -eq 0 -or $final.RetryAllowed -or (Test-Path (Join-Path $fixture 'raw.txt'))){throw 'Mismatched recovery target allowed writes or retries'}
@{Host='recovery-fixture.invalid';Serial='RECOVERY-FIXTURE'}|ConvertTo-Json|Set-Content $recovery
$p=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$controller+'" -Live -SettingsPath "'+$settings+'" -StatusPath "'+$status+'" -Iterations 3') -Wait -PassThru -WindowStyle Hidden
$writes=Get-Content (Join-Path $fixture 'raw.txt')
if($p.ExitCode -ne 0 -or $writes[0] -ne '0 raw 0x30 0x30 0x01 0x01' -or -not($writes|Where-Object{$_ -eq '3 raw 0x30 0x30 0x01 0x00'})){throw 'Recovery did not restore auto before validated takeover'}
'PASS: transient/safety classification, duplicate-name SDR locators, three valid startup samples, simulated telemetry loss, automatic restore and persistent original exit reason. No physical IPMI commands sent.'
