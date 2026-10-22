$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\R730-App-Fleet\Hpe-Redfish.ps1')
. (Join-Path $PSScriptRoot '..\R730-App-Fleet\Redfish-Control.ps1')
$thermal=[pscustomobject]@{Oem=@{Hpe=@{ThermalConfiguration='OptimalCooling';FanPercentMinimum=20}}}
$config=[pscustomobject]@{NativeCoolingProfile='IncreasedCooling';NativeMinimumEnabled=$true;NativeMinimum=50}
$plan=Get-NativeCoolingPlan $config 'HPE' $thermal $null $null '/redfish/v1/Chassis/1/Thermal' '' ''
if($plan.Before.FanPercentMinimum -ne 20 -or $plan.After.FanPercentMinimum -ne 50){throw 'HPE plan failed'}
$invalid=$false;try{Convert-NativePatch HPE @{PowerOff=$true}|Out-Null}catch{$invalid=$true};if(-not $invalid){throw 'Arbitrary OEM patch accepted'}
$mode=[pscustomobject]@{Mode='Standard';'Mode@Redfish.AllowableValues'=@('Standard','FullSpeed')}
$plan=Get-NativeCoolingPlan ([pscustomobject]@{NativeCoolingProfile='FullSpeed'}) 'Supermicro' $null $null $mode '' '' '/redfish/v1/Managers/1/Oem/Supermicro/FanMode'
if($plan.Before.Mode -ne 'Standard' -or $plan.After.Mode -ne 'FullSpeed'){throw 'Supermicro plan failed'}
$plan=Get-NativeCoolingPlan ([pscustomobject]@{NativeCoolingProfile='FullSpeedOverride'}) 'Lenovo' $null ([pscustomobject]@{FansFullSpeedOverrideEnable=$false}) $null '' '/redfish/v1/Chassis/1/ThermalSubsystem' ''
if($plan.After.FansFullSpeedOverrideEnable -ne $true){throw 'Standard override plan failed'}
$invalid=$false;try{Get-NativeCoolingPlan $config 'Unknown' $thermal $null $null '/redfish/v1/Chassis/1/Thermal' '' ''|Out-Null}catch{$invalid=$true};if(-not $invalid){throw 'Unknown vendor enabled OEM control'}

# Run the actual worker against an in-process HTTPS transport fixture. No
# connections or physical fan commands are made by this test.
Add-Type -AssemblyName System.Security
$fixture=Join-Path $PSScriptRoot ('RedfishTest-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $fixture|Out-Null
$settings=Join-Path $fixture 'settings.json';$status=Join-Path $fixture 'status.json';$stop=Join-Path $fixture 'status.stop'
$password=[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes('fixture-only'),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
@{IdracHost='fixture.invalid';IdracUser='fixture';IdracPassProtected=$password;ManagementProvider='HPE';ProfileName='HPE fixture';NativeCoolingProfile='IncreasedCooling';NativeMinimumEnabled=$true;NativeMinimum=50}|ConvertTo-Json|Set-Content $settings
function Invoke-WebRequest {
    param($Uri,$Headers,$Method,[switch]$UseBasicParsing,$TimeoutSec,$MaximumRedirection,$ContentType,$Body)
    if(([uri]$Uri).Host -ne 'fixture.invalid'){throw 'Unexpected external request'}
    $path=([uri]$Uri).AbsolutePath.TrimEnd('/')
    if($Method -eq 'Patch'){
        $global:Mock.Patches++
        if(-not $Headers['If-Match']){throw 'Missing optimistic concurrency guard'}
        if($global:Mock.FailRestore -and $global:Mock.Patches -gt 1){throw 'Simulated restore rejection'}
        $payload=$Body|ConvertFrom-Json;$global:Mock.Mode=$payload.Oem.Hpe.ThermalConfiguration;$global:Mock.Minimum=$payload.Oem.Hpe.FanPercentMinimum
        return [pscustomobject]@{Content='{}'}
    }
    $value=switch($path){
        '/redfish/v1' {@{Systems=@{'@odata.id'='/redfish/v1/Systems'};Chassis=@{'@odata.id'='/redfish/v1/Chassis'}}}
        '/redfish/v1/Systems' {@{Members=@(@{'@odata.id'='/redfish/v1/Systems/1'})}}
        '/redfish/v1/Chassis' {@{Members=@(@{'@odata.id'='/redfish/v1/Chassis/1'})}}
        '/redfish/v1/Systems/1' {if($global:Mock.Patches -gt 0){[IO.File]::WriteAllText($global:Mock.Stop,'stop')};@{Manufacturer='HPE';Model='Fixture';SerialNumber='FIXTURE123';Status=@{Health='OK'}}}
        '/redfish/v1/Chassis/1' {@{Thermal=@{'@odata.id'='/redfish/v1/Chassis/1/Thermal'};Power=@{'@odata.id'='/redfish/v1/Chassis/1/Power'}}}
        '/redfish/v1/Chassis/1/Thermal' {@{'@odata.etag'='"fixture"';Oem=@{Hpe=@{ThermalConfiguration=$global:Mock.Mode;FanPercentMinimum=$global:Mock.Minimum}};Temperatures=@(@{Name='CPU';PhysicalContext='CPU';ReadingCelsius=40;Status=@{Health='OK'}});Fans=@(@{Name='Fan A';Reading=30;ReadingUnits='Percent';Status=@{Health='OK'}})}}
        '/redfish/v1/Chassis/1/Power' {@{PowerControl=@(@{PowerConsumedWatts=200})}}
        default {throw ('Unrecognized fixture path '+$path)}
    }
    return [pscustomobject]@{Content=($value|ConvertTo-Json -Depth 12)}
}
foreach($fail in @($false,$true)){
    if(Test-Path $stop){Remove-Item -LiteralPath $stop}
    $global:Mock=@{Mode='OptimalCooling';Minimum=20;Patches=0;FailRestore=$fail;Stop=$stop}
    & (Join-Path $PSScriptRoot '..\R730-App-Fleet\RedfishWorker.ps1') -SettingsPath $settings -StatusPath $status -StopPath $stop -Live
    $final=Get-Content $status -Raw|ConvertFrom-Json
    $recovery=Join-Path $fixture 'Cooling-Recovery.json'
    if(-not $fail){if($final.Message -ne 'Original native cooling settings verified' -or $global:Mock.Patches -ne 2 -or $global:Mock.Mode -ne 'OptimalCooling' -or $global:Mock.Minimum -ne 20 -or (Test-Path $recovery)){throw ('Native restoration failed: '+$final.Message)}}
    else {if($final.State -ne 'RESTORE FAILED' -or -not(Test-Path $recovery)){throw 'Failed restoration was hidden'}}
}
'PASS: native planning, patch whitelist, HPE write/read-back, ETag, original-setting restore and retained failed-recovery record.'
# Leave the small fixture record available for review; it contains fake credentials only.
