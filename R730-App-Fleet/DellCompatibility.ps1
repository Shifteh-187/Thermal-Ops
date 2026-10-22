# Discovery is read-only. Only explicitly recorded combinations can use raw control.
function Get-DellCompatibility($Identity,[string]$McInfo) {
    $firmware='Unknown';$manufacturerId='';$productId='';$aux=''
    if($McInfo -match '(?im)^Firmware Revision\s*:\s*([0-9]+\.[0-9]+)\s*$'){$firmware=$Matches[1]}
    if($McInfo -match '(?im)^Manufacturer ID\s*:\s*(\d+)'){$manufacturerId=$Matches[1]}
    if($McInfo -match '(?im)^Product ID\s*:\s*(\d+)'){$productId=$Matches[1]}
    if($McInfo -match '(?ims)^Aux Firmware Rev Info\s*:\s*((?:\s*0x[0-9a-f]{2}\s*){4})'){
        $aux=([regex]::Matches($Matches[1],'(?i)0x([0-9a-f]{2})') | ForEach-Object {$_.Groups[1].Value.ToUpperInvariant()}) -join ''
    }
    $dell=$Identity.Manufacturer -match '^(Dell|Dell Inc\.?|Dell EMC)$'
    $model=([string]$Identity.Model -replace '^PowerEdge\s+','').ToUpperInvariant()
    # Explicit examples from Dell's generation table. Do not infer unknown OEM models.
    $generation='Unknown'
    foreach($group in @(
        @{Id='iDRAC6';Models=@('R410','R510','R610','R710','R810','R910','T410','T610','T710')},
        @{Id='iDRAC7';Models=@('R320','R420','R520','R620','R720','R720XD','R820','R920','T320','T420','T620')},
        @{Id='iDRAC8';Models=@('R330','R430','R530','R630','R730','R730XD','R830','R930','T330','T430','T630')},
        @{Id='iDRAC9';Models=@('R340','R440','R540','R640','R740','R740XD','R740XD2','R840','R940','R6415','R7415','R7425','R350','R450','R550','R650','R750','R6515','R6525','R7515','R7525','R360','R660','R760','R6615','R6625','R7615','R7625','T340','T440','T640','T350','T550','T560')},
        @{Id='iDRAC10';Models=@('R470','R570','R6715','R6725','R770','R7715','R7725')}
    )){if($dell -and $model -in $group.Models){$generation=$group.Id}}
    # Fingerprint of the existing R730 deployment, not a claim about every iDRAC8.
    $allowed=$dell -and $model -eq 'R730' -and $manufacturerId -eq '674' -and $productId -eq '256' -and $firmware -eq '2.86' -and $aux -eq '00065656'
    $reason=if($allowed){'Recorded R730/IPMI firmware combination; live telemetry and GPU checks still required'}else{'Unverified model or firmware: monitoring only. Use Dell Redfish for exposed native cooling settings.'}
    [pscustomobject]@{ManualControlAllowed=[bool]$allowed;Reason=$reason;IdracGeneration=$generation;FirmwareRevision=$firmware;FirmwareAux=$aux;FirmwareSource='IPMI mc info (not the full iDRAC release number)';ManufacturerId=$manufacturerId;ProductId=$productId}
}

function Get-MonitorNumber([string]$Text) {
    $number=0.0
    if([double]::TryParse($Text,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -and -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)){return $number}
    return $null
}

function Convert-DellMonitorTelemetry([string]$Raw) {
    $temps=@();$fans=@();$powers=@();$health='TELEMETRY OK';$missing=0
    foreach($line in ($Raw -split '\r?\n')){
        $p=@($line -split '\|');if($p.Count -lt 3){continue}
        $name=$p[0].Trim();$unit=$p[2].Trim();if($unit -notin @('degrees C','RPM','Watts')){continue}
        $value=Get-MonitorNumber $p[1].Trim();$status=if($p.Count -gt 3){$p[3].Trim()}else{'unknown'}
        # Preserve unhealthy/missing rows for diagnosis, never turn missing power into zero.
        if($null -ne $value -and (($unit -eq 'degrees C' -and ($value -lt -20 -or $value -gt 150)) -or ($unit -ne 'degrees C' -and ($value -lt 0 -or $value -gt 100000)))){$value=$null}
        if($null -eq $value){$missing++}
        elseif($status -notin @('ok','ns')){$health='ATTENTION'}
        elseif($status -eq 'ns' -and $health -eq 'TELEMETRY OK'){$health='DEGRADED'}
        if($null -ne $value -and $p.Count -ge 10){
            foreach($column in @(7,8,9)){$limit=Get-MonitorNumber $p[$column].Trim();if($null -ne $limit -and $value -ge $limit){$health='ATTENTION'}}
            foreach($column in @(4,5,6)){$limit=Get-MonitorNumber $p[$column].Trim();if($null -ne $limit -and $value -le $limit){$health='ATTENTION'}}
        }
        if($unit -eq 'RPM' -and $null -ne $value -and $value -eq 0){$health='ATTENTION'}
        $sensor=[pscustomobject]@{Name=$name;Value=$value;Units=$unit;Status=$status}
        switch($unit){'degrees C' {$temps+=$sensor};'RPM' {$fans+=$sensor};'Watts' {if($name -match '^(Pwr Consumption|Power Consumption|System Power|Total Power)$'){$powers+=$sensor}}}
    }
    $valid=@($temps | Where-Object {$null -ne $_.Value})
    if($valid.Count -eq 0 -or $fans.Count -eq 0 -or $missing -gt 0){if($health -eq 'TELEMETRY OK'){$health='DEGRADED'}}
    if($temps.Count -eq 0 -and $fans.Count -eq 0){$health='UNKNOWN'}
    $cpu=@($valid | Where-Object {$_.Name -eq 'Temp' -or $_.Name -match '(?i)(CPU|Processor).*Temp|Temp.*(CPU|Processor)'})
    $inlet=@($valid | Where-Object {$_.Name -match '(?i)Inlet|Intake|Ambient'})
    $exhaust=@($valid | Where-Object {$_.Name -match '(?i)Exhaust|Outlet'})
    $hot=$valid | Sort-Object Value -Descending | Select-Object -First 1
    [pscustomobject]@{Temps=$temps;Fans=$fans;Watts=$(if($powers.Count -eq 1){$powers[0].Value}else{$null});CpuMax=($cpu|Measure-Object Value -Maximum).Maximum;Inlet=($inlet|Measure-Object Value -Maximum).Maximum;Exhaust=($exhaust|Measure-Object Value -Maximum).Maximum;SystemMax=$(if($hot){$hot.Value}else{$null});HottestSystemSensor=$(if($hot){$hot.Name}else{'Unknown'});ReportedHealth=$health}
}
