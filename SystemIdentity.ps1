# Read-only FRU identity. Control eligibility is evaluated separately.
function Get-TargetSystemSerial {
    param([string]$Raw)
    $blocks=[regex]::Matches($Raw,'(?ims)^\s*FRU Device Description\s*:\s*([^\r\n]+)\r?\n(.*?)(?=^\s*FRU Device Description\s*:|\z)')
    $body=$Raw
    if ($blocks.Count) {
        $system=@($blocks | Where-Object { $_.Groups[1].Value -match '\(ID\s+0\)' })
        if(-not $system.Count){return $null}
        $body=$system[0].Groups[2].Value
    }
    if($body -match '(?im)^\s*Product Serial\s*:\s*([^\r\n]+)'){return $Matches[1].Trim()}
    return $null
}
function Convert-TargetIdentity {
    param([string]$Raw)
    $body=$Raw
    $blocks=[regex]::Matches($Raw,'(?ims)^\s*FRU Device Description\s*:\s*([^\r\n]+)\r?\n(.*?)(?=^\s*FRU Device Description\s*:|\z)')
    if ($blocks.Count) {
        $system=@($blocks | Where-Object { $_.Groups[1].Value -match '\(ID\s+0\)' })
        $body=if($system.Count){$system[0].Groups[2].Value}else{''}
    }
    $model='Unknown model';$manufacturer='Unknown manufacturer'
    if ($body -match '(?im)^\s*Product Name\s*:\s*([^\r\n]+)') { $model=$Matches[1].Trim() }
    if ($body -match '(?im)^\s*Product Manufacturer\s*:\s*([^\r\n]+)') { $manufacturer=$Matches[1].Trim() }
    elseif ($body -match '(?im)^\s*Board Mfg\s*:\s*([^\r\n]+)') { $manufacturer=$Matches[1].Trim() }
    [pscustomobject]@{Manufacturer=$manufacturer;Model=$model;Source='iDRAC FRU';
        CoolingProfile=$(if($model -eq 'PowerEdge R730'){'Dell R730'}else{'Unsupported for manual control'})}
}
