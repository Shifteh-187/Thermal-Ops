$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\R730-App-Fleet\Hpe-Redfish.ps1')
$system=[pscustomobject]@{Status=@{Health='OK'}}
$thermal=[pscustomobject]@{Temperatures=@(@{Name='CPU 1';PhysicalContext='CPU';ReadingCelsius=45;UpperThresholdCritical=90;Status=@{Health='OK'}},@{Name='Inlet';ReadingCelsius=22;Status=@{Health='OK'}});Fans=@(@{Name='Fan A';Reading=36;ReadingUnits='Percent';Status=@{Health='OK'}},@{Name='Fan B';Reading=3200;ReadingUnits='RPM';Status=@{Health='OK'}})}
$power=[pscustomobject]@{PowerControl=@(@{PowerConsumedWatts=315})}
$result=Convert-HpeTelemetry $system $thermal $power
if ($result.Watts -ne 315 -or $result.CpuMax -ne 45 -or $result.Inlet -ne 22 -or $result.Fans[0].Units -ne 'Percent' -or $result.Fans[1].Value -ne 3200 -or $result.ReportedHealth -ne 'TELEMETRY OK') {throw 'HPE normal telemetry mapping failed'}
$thermal.Temperatures[0].ReadingCelsius=95
if ((Convert-HpeTelemetry $system $thermal $power).ReportedHealth -ne 'ATTENTION') {throw 'HPE critical threshold failed'}
$thermal.Temperatures[0].ReadingCelsius=45
$thermal.Fans[0].Reading=150
if ((Convert-HpeTelemetry $system $thermal $power).ReportedHealth -ne 'DEGRADED') {throw 'HPE percent validation failed'}
$power.PowerControl=@(@{PowerConsumedWatts=100},@{PowerConsumedWatts=200})
if ($null -ne (Convert-HpeTelemetry $system $thermal $power).Watts) {throw 'HPE overlapping power domains counted'}
$empty=Convert-HpeTelemetry ([pscustomobject]@{}) $null $null
if ($empty.ReportedHealth -ne 'UNKNOWN' -or $null -ne $empty.Watts -or $null -ne $empty.CpuMax) {throw 'Missing HPE readings shown healthy or zero'}
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\R730-App-Fleet\HpeMonitor.ps1'),[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) {throw ($errors | Out-String)}
'PASS: HPE mapping, units, health thresholds, missing data, power domains and worker syntax.'

$thermal.Fans[0].Reading=0
if((Convert-HpeTelemetry $system $thermal $power).ReportedHealth -ne 'ATTENTION'){throw 'Zero fan not flagged'}
$thermal.Fans[0].Reading=30;$thermal.Temperatures[0].ReadingCelsius=$null
if((Convert-HpeTelemetry $system $thermal $power).ReportedHealth -ne 'DEGRADED'){throw 'Partial temperatures accepted for native control'}
'PASS: zero-fan and partially missing temperature guards.'
