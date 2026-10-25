function Assert-CustomFanSettings($Settings) {
    $mode=[string]$Settings.FanCurveMode
    if(-not $mode){return}
    if($mode -notin @('Original','Smart','Custom','Manual')){throw 'Unknown fan curve mode'}
    if($mode -eq 'Manual'){$null=Convert-Number $Settings.ManualFanPercent 10 100}
    if($mode -ne 'Custom'){return}
    $curves=@($Settings.FanCurves|Where-Object{$_.Enabled -eq $true})
    if($curves.Count -lt 1 -or $curves.Count -gt 32){throw 'Custom mode requires 1-32 sensor curves'}
    $seen=@{}
    foreach($curve in $curves){
        $source=[string]$curve.Source
        if($source -notmatch '^(CpuMax|GpuMax|Exhaust|Inlet|SystemMax|Temp:.{1,80}:\d{1,3})$' -or $seen.ContainsKey($source)){throw 'Invalid or duplicate curve sensor'}
        $seen[$source]=$true;$points=@($curve.Points)
        if($points.Count -lt 2 -or $points.Count -gt 12){throw 'Each curve requires 2-12 points'}
        $lastTemp=-1.0;$lastPercent=0.0
        foreach($point in $points){
            $temp=Convert-Number $point.Temperature 0 100;$percent=Convert-Number $point.Percent 10 100
            if($temp -le $lastTemp -or $percent -lt $lastPercent){throw 'Curve temperatures must increase and fan percentages must not decrease'}
            $lastTemp=$temp;$lastPercent=$percent
        }
    }
}
function Get-CurvePercent($Points,[double]$Temperature) {
    $p=@($Points);if($Temperature -le $p[0].Temperature){return [double]$p[0].Percent}
    for($i=1;$i -lt $p.Count;$i++){
        if($Temperature -le $p[$i].Temperature){$ratio=($Temperature-$p[$i-1].Temperature)/($p[$i].Temperature-$p[$i-1].Temperature);return $p[$i-1].Percent+$ratio*($p[$i].Percent-$p[$i-1].Percent)}
    }
    return [double]$p[-1].Percent
}
function Get-CustomCurveTarget($Settings,$Ipmi,$Gpu,[int]$SafetyTarget) {
    if($Settings.FanCurveMode -eq 'Manual'){return [int][math]::Ceiling([math]::Max($SafetyTarget,[double]$Settings.ManualFanPercent))}
    if($Settings.FanCurveMode -ne 'Custom'){return $SafetyTarget}
    $target=$SafetyTarget
    foreach($curve in @($Settings.FanCurves|Where-Object{$_.Enabled -eq $true})){
        $value=switch -Regex ([string]$curve.Source){
            '^CpuMax$'{$Ipmi.CpuMax;break}
            '^GpuMax$'{$Gpu.Temp;break}
            '^Exhaust$'{$Ipmi.Exhaust;break}
            '^Inlet$'{$Ipmi.Inlet;break}
            '^SystemMax$'{$Ipmi.SystemMax;break}
            '^Temp:(.*):(\d+)$'{$samples=@($Ipmi.Temps|Where-Object Name -eq $Matches[1]);$index=[int]$Matches[2];if($index -lt $samples.Count){$samples[$index].Value};break}
        }
        if($null -eq $value){throw 'Custom curve sensor unavailable; complete telemetry required'}
        $value=Convert-Number $value -20 150
        $target=[math]::Max($target,(Get-CurvePercent $curve.Points $value))
    }
    return [int][math]::Ceiling($target)
}
