$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'R730-FanController.ps1'
$tokens=$null; $errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
. $path -LibraryOnly
$script:Checks=0
function Assert($Condition,$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:Checks++
}
function Assert-Throws([scriptblock]$Code,$Message) {
    $threw=$false
    try { & $Code | Out-Null } catch { $threw=$true }
    Assert $threw $Message
}
$fixture=@'
Temp | 40 | degrees C | ok
Temp | 42 | degrees C | ok
Inlet Temp | 22 | degrees C | ok
Exhaust Temp | 34 | degrees C | ok
PCIe Temp | 45 | degrees C | ok
Fan1 | 3000 | RPM | ok
Fan2 | 3000 | RPM | ok
Fan3 | 3000 | RPM | ok
Fan4 | 3000 | RPM | ok
Fan5 | 3000 | RPM | ok
Fan6 | 3000 | RPM | ok
'@
$ipmi=Convert-IpmiTelemetry $fixture
$gpu=Convert-GpuTelemetry "40, 0, 20`n70, 90, 150"
Assert ($gpu.Count -eq 2 -and $gpu.Temp -eq 70 -and $gpu.Util -eq 90) 'all GPU rows'
Assert ($ipmi.CpuMax -eq 42 -and $ipmi.SystemMax -eq 45) 'R730 sensor classification'
Assert-Throws { Convert-IpmiTelemetry ($fixture.Replace('Temp | 42','Missing | 42')) } 'missing CPU'
Assert-Throws { Convert-IpmiTelemetry ($fixture.Replace('Fan6 | 3000','Fan6 | 0')) } 'stalled fan'
Assert-Throws { Convert-GpuTelemetry '40, N/A, 20' } 'invalid GPU value'
Assert-Throws { Convert-Number 'NaN' 0 150 } 'nonfinite value'
Assert-Throws { Set-FanPercent 0 } 'unsafe command rejected'
Assert-SensorInventory $ipmi $gpu
Assert-Throws { Assert-SensorInventory (Convert-IpmiTelemetry ($fixture.Replace('PCIe Temp | 45 | degrees C | ok',''))) $gpu } 'disappearing system sensor'
$gpu.Temp=83
Assert ((Get-ControlTarget $ipmi $gpu 0) -eq 100 -and $EmergencyMode) 'emergency enters'
$gpu.Temp=72
Assert ((Get-ControlTarget $ipmi $gpu 2) -eq 100) 'emergency recovery hysteresis'
$gpu.Temp=71; $gpu.Util=0; $gpu.Power=20
$null=Get-ControlTarget $ipmi $gpu 4
Assert (-not $EmergencyMode) 'emergency recovers'
$gpu.Temp=40
Assert ((Get-ControlTarget $ipmi $gpu 5) -eq 55) 'post-load hold'
Assert ((Get-ControlTarget $ipmi $gpu 125) -eq 18) 'post-load expires'
Assert ((Get-SmoothedTarget 100 10 0) -eq 100) 'immediate increase'
Assert ((Get-SmoothedTarget 10 100 1) -eq 100) 'decrease held'
Assert ((Get-SmoothedTarget 10 100 21) -eq 97) 'bounded decrease'
Assert ((Get-SmoothedTarget 99 97 22) -eq 99) 'small increases never blocked'
Assert ((Get-GpuFanTarget 68) -eq 45 -and (Get-CpuFanTarget 85) -eq 55 -and (Get-ExhaustFanTarget 55) -eq 44 -and (Get-SystemFanTarget 84) -eq 70) 'original curve boundaries'
$Live=$true
$ResponseCheck=[pscustomobject]@{Time=0; Fans=$ipmi.Fans}
Assert-Throws { Test-FanResponse $ipmi 31 } 'missing RPM response'
$Live=$false
$IpmiExe='does-not-exist'
Set-FanPercent 100
Assert $true 'monitor mode performs no writes'
Write-Host "$Checks offline checks passed. No hardware commands executed."
