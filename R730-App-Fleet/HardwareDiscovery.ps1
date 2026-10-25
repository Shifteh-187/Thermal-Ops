# Read-only locator parsing. SDR sensor numbers are query identifiers, not fan-write opcodes.
function Convert-SdrLocators([string]$Raw) {
    $result=@()
    foreach($line in $Raw -split '\r?\n'){
        $p=@($line -split '\|');if($p.Count -lt 4){continue}
        $number=$p[1].Trim();$entity=$p[3].Trim()
        if($number -notmatch '^[0-9a-fA-F]{2}h$' -or $entity -notmatch '^\d{1,3}\.\d{1,3}$'){continue}
        $result += [pscustomobject]@{Kind='IPMI SDR';Name=$p[0].Trim();SensorNumber=('0x'+$number.Substring(0,2).ToUpperInvariant());EntityId=$entity;Status=$p[2].Trim()}
        if($result.Count -ge 128){break}
    }
    return $result
}
