$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot ('MsiBuild\Probe-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $fixture -Force|Out-Null
foreach($name in @('ProbeHardware.ps1','HardwareDiscovery.ps1')){Copy-Item (Join-Path $PSScriptRoot ('..\R730-App-Fleet\'+$name)) $fixture}
$fake=Join-Path $fixture 'fake-ipmi.exe'
Add-Type -TypeDefinition @'
using System;using System.IO;
class ProbeFixture {
 static void Main(string[] args){
  if(Array.IndexOf(args,"raw")>=0||Array.IndexOf(args,"-P")>=0)Environment.Exit(91);
  if(Environment.GetEnvironmentVariable("IPMI_PASSWORD")!="fixture-password")Environment.Exit(92);
  string command=String.Join(" ",args);File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"calls.txt"),command+"\n");
  if(command.EndsWith("mc info"))Console.WriteLine("Firmware Revision : 1.00\nManufacturer ID : 42\nProduct ID : 7");
  else if(command.EndsWith("fru print"))Console.WriteLine("Product Manufacturer : Generic vendor\nProduct Name : Arbitrary server\nProduct Serial : PRIVATE-SERIAL");
  else if(command.EndsWith("sdr elist all"))Console.WriteLine("CPU Temp | 01h | ok | 3.1 | 40 degrees C\nFan1 | 30h | ok | 29.1 | 4000 RPM");
  else if(command.EndsWith("sensor"))Console.WriteLine("CPU Temp | 40 | degrees C | ok\nFan1 | 4000 | RPM | ok\nPower | 123 | Watts | ok");
  else Environment.Exit(93);
 }
}
'@ -OutputAssembly $fake -OutputType ConsoleApplication
Add-Type -AssemblyName System.Security
$password=[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes('fixture-password'),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
$settings=Join-Path $fixture 'settings.json';$output=Join-Path $fixture 'result.json'
@{ManagementProvider='UnknownVendor';IpmiExe=$fake;UseBundledIpmi=$false;IdracHost='fixture.invalid';IdracUser='fixture';IdracPassProtected=$password}|ConvertTo-Json|Set-Content $settings
$script:gets=New-Object Collections.Generic.List[string]
function Invoke-WebRequest {
    param($Uri,$Headers,$Method,$UseBasicParsing,$TimeoutSec,$MaximumRedirection)
    if($Method -ne 'Get'){throw 'Probe attempted a non-GET request'}
    $path=([Uri]$Uri).AbsolutePath;$script:gets.Add($path)
    $body=switch($path){
        '/redfish/v1/' {@{Name='Root'}}
        '/redfish/v1/Systems' {@{Members=@(@{'@odata.id'='/redfish/v1/Systems/1'})}}
        '/redfish/v1/Chassis' {@{Members=@(@{'@odata.id'='/redfish/v1/Chassis/1'},@{'@odata.id'='https://foreign.invalid/redfish/v1/evil'})}}
        '/redfish/v1/Managers' {@{Members=@()}}
        '/redfish/v1/Systems/1' {@{Name='Generic system';Manufacturer='Generic vendor';Model='Unrecognised model';SerialNumber='PRIVATE-SERIAL'}}
        '/redfish/v1/Chassis/1' {@{Name='Chassis';Thermal=@{'@odata.id'='/redfish/v1/Chassis/1/Thermal'}}}
        '/redfish/v1/Chassis/1/Thermal' {@{Name='Thermal';Temperatures=@(@{Name='CPU';ReadingCelsius=42;MemberId='0'});Fans=@(@{Name='Fan1';Reading=4000;ReadingUnits='RPM';MemberId='0'})}}
        default {throw 'Unexpected query'}
    }
    [pscustomobject]@{Content=($body|ConvertTo-Json -Depth 8 -Compress)}
}
& (Join-Path $fixture 'ProbeHardware.ps1') -SettingsPath $settings -OutputPath $output
$raw=Get-Content $output -Raw;$result=$raw|ConvertFrom-Json
if(-not $result.Complete -or @($result.Rows).Count -lt 10 -or @($result.Checks).Count -lt 8){throw 'Generic server discovery did not complete'}
if($raw -match 'PRIVATE-SERIAL|fixture-password|fixture.invalid|foreign.invalid|Authorization'){throw 'Private credentials or identifiers leaked into probe results'}
if(@($gets|Where-Object{$_ -like '*evil*'}).Count -ne 0){throw 'Foreign Redfish link was followed'}
if((Get-Content (Join-Path $fixture 'calls.txt')).Count -ne 4){throw 'Unexpected IPMI probe commands'}
if(@($result.HardwareDiscovery|Where-Object SensorNumber -eq '0x30').Count -ne 1){throw 'SDR identifiers absent'}
'PASS: generic server IPMI/Redfish discovery, exact read-only command set, password environment, query counts, foreign-resource rejection and private-field scrubbing. No network/hardware writes.'
$localFolder=Join-Path $fixture 'LocalHardware';New-Item -ItemType Directory -Path $localFolder|Out-Null
Add-Type -TypeDefinition @'
using System;using System.IO;
class LocalProbeFixture {static void Main(string[] args){if(args.Length!=2||args[0]!="--probe")Environment.Exit(99);File.WriteAllText(args[1],"{\"Sensors\":[{\"Id\":\"/controller/0/control/0\",\"Name\":\"USB fan channel\",\"Type\":\"Control\",\"Value\":40,\"Units\":\"%\",\"Access\":\"Driver exposes control; writes not tested\"},{\"Id\":\"/gpu-nvidia/0/temperature/0\",\"Name\":\"GPU core\",\"Type\":\"Temperature\",\"Value\":50,\"Units\":\"C\",\"Access\":\"Read only\"}]}");}}
'@ -OutputAssembly (Join-Path $localFolder 'LocalWorker.exe') -OutputType ConsoleApplication
function Get-CimInstance {param($ClassName,$OperationTimeoutSec,$ErrorAction);[pscustomobject]@{Name='Gaming device';Model='Gaming PC';Manufacturer='Fixture vendor';SerialNumber='PRIVATE-LOCAL-SERIAL';PNPDeviceID='PCI\VEN_10DE&DEV_2504\PRIVATE-INSTANCE'}}
@{ManagementProvider='Local';IdracHost='local-fixture';IdracPassProtected=''}|ConvertTo-Json|Set-Content $settings
$before=$script:gets.Count
& (Join-Path $fixture 'ProbeHardware.ps1') -SettingsPath $settings -OutputPath $output
$raw=Get-Content $output -Raw;$result=$raw|ConvertFrom-Json
if(-not $result.Complete -or @($result.Rows|Where-Object Backend -eq 'Local').Count -ne 2 -or $script:gets.Count -ne $before){throw 'Local-only discovery mixed in remote queries or lost sensors'}
if($raw -match 'PRIVATE-LOCAL-SERIAL|PRIVATE-INSTANCE'){throw 'Private local device instance leaked'}
if(@($result.Rows|Where-Object Identifier -eq 'PCI VEN_10DE&DEV_2504').Count -lt 1){throw 'Non-unique PCI vendor/device signature missing'}
'PASS: gaming-PC Windows inventory and driver sensor/control discovery; local-only scan skips remote targets and omits serial/device-instance identifiers.'
