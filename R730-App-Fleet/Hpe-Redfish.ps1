function Get-HpeNumber($Value) {
    if ($null -eq $Value) { return $null }
    $number=0.0
    if ([double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -and -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) { return $number }
    return $null
}
function Convert-HpeTelemetry($System,$Thermal,$Power) {
    $temps=@();$fans=@();$health=@([string]$System.Status.HealthRollup,[string]$System.Status.Health)
    foreach ($item in @($Thermal.Temperatures)) {
        if ($null -eq $item -or $item.Status.State -in @('Absent','Disabled')) { continue }
        $value=Get-HpeNumber $item.ReadingCelsius
        if ($null -eq $value -or $value -lt -20 -or $value -gt 150) { continue }
        $temps+=@{Name=[string]$item.Name;Value=$value;Context=[string]$item.PhysicalContext}
        $health += [string]$item.Status.Health
        $limit=Get-HpeNumber $item.UpperThresholdCritical
        if ($null -ne $limit -and $value -ge $limit) { $health+='Critical' }
    }
    foreach ($item in @($Thermal.Fans)) {
        if ($null -eq $item -or $item.Status.State -in @('Absent','Disabled')) { continue }
        $value=Get-HpeNumber $item.Reading
        $units=[string]$item.ReadingUnits
        if ($null -ne $value -and ($value -lt 0 -or ($units -eq 'Percent' -and $value -gt 100))) { $value=$null }
        $fans+=@{Name=[string]$item.Name;Value=$value;Units=$units}
        $health += [string]$item.Status.Health
    }
    $health += [string]$Thermal.Status.HealthRollup
    $health += [string]$Power.Status.HealthRollup
    $state='UNKNOWN'
    if ($health -contains 'Critical') { $state='ATTENTION' }
    elseif ($health -contains 'Warning') { $state='DEGRADED' }
    elseif ($health -contains 'OK') { $state='TELEMETRY OK' }
    if (($temps.Count -eq 0 -or $fans.Count -eq 0 -or @($fans | Where-Object {$null -eq $_.Value}).Count -gt 0) -and $state -eq 'TELEMETRY OK') { $state='DEGRADED' }
    $watts=$null
    # PowerControl is a whole-chassis measurement. Do not sum PSU output or
    # multiple domains, which could count the same consumption twice.
    $domains=@($Power.PowerControl | Where-Object {$null -ne $_})
    if ($domains.Count -eq 1) { $watts=Get-HpeNumber $domains[0].PowerConsumedWatts;if ($null -ne $watts -and $watts -lt 0) {$watts=$null} }
    $cpu=@($temps | Where-Object {$_.Context -eq 'CPU' -or $_.Name -match 'CPU|Processor'})
    $inlet=@($temps | Where-Object {$_.Context -in @('Intake','Ambient') -or $_.Name -match 'Inlet|Ambient'})
    $exhaust=@($temps | Where-Object {$_.Context -eq 'Exhaust' -or $_.Name -match 'Exhaust'})
    return @{Temps=$temps;Fans=$fans;Watts=$watts;CpuMax=($cpu | ForEach-Object {$_.Value} | Measure-Object -Maximum).Maximum;Inlet=($inlet | ForEach-Object {$_.Value} | Measure-Object -Maximum).Maximum;Exhaust=($exhaust | ForEach-Object {$_.Value} | Measure-Object -Maximum).Maximum;SystemMax=($temps | ForEach-Object {$_.Value} | Measure-Object -Maximum).Maximum;HottestSystemSensor='HPE reported sensors';ReportedHealth=$state}
}
