$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'R730-FanController-Smart.ps1') -LibraryOnly
$checks=0
function Assert($Condition,$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++
}
$ipmi=[pscustomobject]@{CpuMax=40; Exhaust=30; SystemMax=$null}
$gpu=[pscustomobject]@{Temp=60; Util=0; Power=30}
# Sweep every half-degree across all original curves: smart blending cannot
# lower demand at any point, including just above each step boundary.
$curves=@(
    @('Get-GpuFanTarget',@(40,45,55,62,68,74),@(10,14,24,28,45,85,100)),
    @('Get-CpuFanTarget',@(40,45,55,62,70,78,85),@(10,14,22,26,32,40,55,100)),
    @('Get-ExhaustFanTarget',@(34,38,42,46,50,55),@(10,16,24,30,36,44,100)),
    @('Get-SystemFanTarget',@(40,50,60,70,78,84),@(10,18,26,36,50,70,100))
)
foreach ($curve in $curves) {
    $previous=0
    for ($temp=0; $temp -le 100; $temp+=0.5) {
        $value=Get-ForwardCurve $temp $curve[1] $curve[2]
        $baseline=& $curve[0] ([int]$temp)
        Assert ($value -ge $baseline -and $value -ge $previous -and $value -le 100) "$($curve[0]) safety floor/monotonic at $temp"
        $previous=$value
    }
}
$base=Get-ControlTarget $ipmi $gpu 0
$flat=Get-SmartTarget $ipmi $gpu 0 $base
Assert ($flat -ge $base) 'baseline floor'
$gpu.Temp=61; $null=Get-SmartTarget $ipmi $gpu 10 (Get-ControlTarget $ipmi $gpu 10)
$gpu.Temp=62; $rising=Get-SmartTarget $ipmi $gpu 20 (Get-ControlTarget $ipmi $gpu 20)
Assert ($SmartRates.GPU -gt 0 -and $SmartReason -like 'Predicting*') 'rising trend detected'
Assert ($rising -ge (Get-ForwardCurve 62 $curves[0][1] $curves[0][2])) 'prediction adds cooling'
$gpu.Temp=40; $gpu.Util=95
Assert ((Get-SmartTarget $ipmi $gpu 30 (Get-ControlTarget $ipmi $gpu 30)) -ge 65) 'load boost'
$gpu.Util=0; $LastGpuLoadTime=0; $SmartHistory=@()
foreach ($t in @(125,135,145)) {
    $gpu.Temp=40+($t-125)/10
    $target=Get-SmartTarget $ipmi $gpu $t (Get-ControlTarget $ipmi $gpu $t)
}
Assert ($target -ge 55 -and $SmartReason -like 'Heat-soak*') 'rising heat extends cooldown'
$target=Get-SmartTarget $ipmi $gpu 310 (Get-ControlTarget $ipmi $gpu 310)
Assert ($target -lt 55 -and $SmartHistory.Count -eq 1) 'stale history discarded and hold expires'
$gpu.Temp=83
Assert ((Get-SmartTarget $ipmi $gpu 312 (Get-ControlTarget $ipmi $gpu 312)) -eq 100) 'emergency unchanged'
$gpu.Temp=72
Assert ((Get-SmartTarget $ipmi $gpu 314 (Get-ControlTarget $ipmi $gpu 314)) -eq 100) 'emergency latch unchanged'
$gpu.Temp=40; $EmergencyMode=$false; $SmartHistory=@(); $LastGpuLoadTime=$null
foreach ($t in @(0,10,20)) {
    $gpu.Temp=45-$t/10
    $target=Get-SmartTarget $ipmi $gpu $t (Get-ControlTarget $ipmi $gpu $t)
}
Assert ($SmartRates.GPU -lt 0 -and $target -ge (Get-ControlTarget $ipmi $gpu 20)) 'falling trend cannot undercut baseline'
$sdr=@'
Temp | 0Eh | ok | 3.1 | 43 degrees C
Temp | 0Fh | ok | 3.2 | 44 degrees C
Inlet Temp | 04h | ok | 7.1 | 24 degrees C
Exhaust Temp | 01h | ok | 7.1 | 30 degrees C
Fan1 | 30h | ok | 7.1 | 3000 RPM
Fan2 | 31h | ok | 7.1 | 3000 RPM
Fan3 | 32h | ok | 7.1 | 3000 RPM
Fan4 | 33h | ok | 7.1 | 3000 RPM
Fan5 | 34h | ok | 7.1 | 3000 RPM
Fan6 | 35h | ok | 7.1 | 3000 RPM
Pwr Consumption | 77h | ok | 7.1 | 378 Watts
'@
$parsed=Convert-SdrTelemetry $sdr
Assert ($parsed.CpuMax -eq 44 -and $parsed.Fans.Count -eq 6 -and $parsed.Watts -eq 378) 'SDR format classification'
$threw=$false
try { Convert-SdrTelemetry ($sdr.Replace('44 degrees C','No Reading')) | Out-Null } catch { $threw=$true }
Assert $threw 'SDR missing temperature rejected'
$threw=$false
try { Convert-SdrTelemetry ($sdr.Replace('0Fh | ok','0Fh | cr')) | Out-Null } catch { $threw=$true }
Assert $threw 'SDR unhealthy sensor rejected'
Write-Host "$checks smart-control checks passed; no hardware commands executed."
