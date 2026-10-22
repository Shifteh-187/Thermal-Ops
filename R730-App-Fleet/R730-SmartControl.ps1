# Additive smart cooling: original curves and emergency logic remain the floor.
$SmartHistory = @()
$SmartReason = 'Original curves'
$SmartRates = @{}

function Convert-SdrTelemetry {
    param([string]$Raw)
    # Extended full SDR rows include sensor ID and entity, followed by reading.
    # Reuse the validated original parser after normalising this documented format.
    $normalised=@(foreach ($line in ($Raw -split '\r?\n')) {
        $parts=@($line -split '\|')
        if ($parts.Count -ne 5) { continue }
        $reading=$parts[4].Trim()
        if ($reading -match '^([-+]?[0-9]+(?:\.[0-9]+)?)\s+(degrees C|RPM|Watts)$') {
            '{0}|{1}|{2}|{3}' -f $parts[0].Trim(),$Matches[1],$Matches[2],$parts[2].Trim()
        }
    })
    Convert-IpmiTelemetry ($normalised -join "`n")
}
function Get-IpmiTelemetry {
    # Full analogue records retain temperatures, fans and power; avoid fetching
    # every discrete sensor and every threshold on each cycle.
    Convert-SdrTelemetry (Invoke-Ipmi @('sdr','elist','full'))
}

function Get-ForwardCurve {
    param([double]$Temperature, [double[]]$Knots, [double[]]$Values)
    # Interpolate towards the NEXT step without ever undercutting the step curve.
    if ($Temperature -le $Knots[0]) { return [int]$Values[0] }
    for ($j=1; $j -lt $Knots.Count; $j++) {
        if ($Temperature -le $Knots[$j]) {
            $fraction=($Temperature-$Knots[$j-1])/($Knots[$j]-$Knots[$j-1])
            return [int][math]::Ceiling($Values[$j]+$fraction*($Values[$j+1]-$Values[$j]))
        }
    }
    return [int]$Values[-1]
}

function Get-SmartTarget {
    param($Ipmi,$Gpu,[double]$Seconds,[int]$Baseline)
    $current=[pscustomobject]@{Time=$Seconds; GPU=$Gpu.Temp; CPU=$Ipmi.CpuMax;
        Exhaust=$Ipmi.Exhaust; System=$Ipmi.SystemMax}
    # Discard history across long collection gaps; never predict from stale pairs.
    if ($SmartHistory.Count -gt 0 -and ($Seconds-$SmartHistory[-1].Time -gt 45 -or $Seconds -le $SmartHistory[-1].Time)) {
        $script:SmartHistory=@()
    }
    $script:SmartHistory=@(@($SmartHistory)+$current | Select-Object -Last 4)
    $script:SmartRates=@{}
    $script:SmartReason='Curve blending'
    $targets=@($Baseline)
    $specs=@{
        GPU=@(@(40,45,55,62,68,74),@(10,14,24,28,45,85,100))
        CPU=@(@(40,45,55,62,70,78,85),@(10,14,22,26,32,40,55,100))
        Exhaust=@(@(34,38,42,46,50,55),@(10,16,24,30,36,44,100))
        System=@(@(40,50,60,70,78,84),@(10,18,26,36,50,70,100))
    }
    foreach ($name in @('GPU','CPU','Exhaust','System')) {
        if ($null -eq $current.$name) { continue }
        $rate=0.0
        # Three samples and >=4 seconds reduce one-sample quantisation noise.
        if ($SmartHistory.Count -ge 3) {
            $first=$SmartHistory[0]; $dt=$Seconds-$first.Time
            if ($dt -ge 4 -and $null -ne $first.$name) {
                $rate=($current.$name-$first.$name)/$dt
            }
        }
        $script:SmartRates[$name]=$rate
        # Predict at most 5 C ahead over 10 seconds; cooling trends never subtract.
        $lead=[math]::Min(5.0,[math]::Max(0.0,$rate)*10.0)
        $predicted=$current.$name+$lead
        $spec=$specs[$name]
        $targets+=Get-ForwardCurve $predicted $spec[0] $spec[1]
        if ($lead -ge 0.5) { $script:SmartReason="Predicting $name rise (+$([math]::Round($lead,1)) C)" }
    }
    # Existing 65% utilisation / 100 W triggers still supply the original 55% floor.
    # Stronger load gets a modest early boost, independent of the temperature trend.
    if ($Gpu.Util -ge 90 -or $Gpu.Power -ge (2*$GpuLoadPowerThreshold)) {
        $targets+=65
        $script:SmartReason='Heavy GPU load: 65% minimum'
    }
    # Retain the full original 120-second hold, extending only while heat is rising.
    # Never hold indefinitely on noise: extension expires 300 s after last load.
    if ($null -ne $LastGpuLoadTime -and $Seconds-$LastGpuLoadTime -ge $CooldownSeconds -and
        $Seconds-$LastGpuLoadTime -lt 300 -and $SmartHistory.Count -ge 3) {
        $rising=@($SmartRates.Values | Where-Object { $_ -gt 0.02 }).Count -gt 0
        if ($rising) {
            $targets+=$CooldownFanPercent
            $script:CooldownRemaining=[int][math]::Ceiling(300-($Seconds-$LastGpuLoadTime))
            $script:SmartReason='Heat-soak hold: temperatures still rising'
        }
    }
    if ($EmergencyMode) { $script:SmartReason='Emergency: original thresholds'; return 100 }
    return [int][math]::Min(100,(($targets | Measure-Object -Maximum).Maximum))
}
