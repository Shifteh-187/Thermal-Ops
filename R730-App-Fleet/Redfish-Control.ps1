# Pure planning/validation functions. Network I/O is confined to RedfishWorker.
function Get-NativeCoolingPlan($Config,$Manufacturer,$Thermal,$Subsystem,$FanMode,[string]$ThermalPath,[string]$SubsystemPath,[string]$FanModePath) {
    $selection=[string]$Config.NativeCoolingProfile
    $before=@{};$after=@{};$kind='';$path=''
    if ($Manufacturer -match 'HPE|Hewlett|HP\b' -and $selection -ne 'FullSpeedOverride') {
        $kind='HPE';$path=$ThermalPath
        $profiles=@('OptimalCooling','IncreasedCooling','MaximumCooling','EnhancedCooling')
        if ($selection -notin $profiles -or [string]$Thermal.Oem.Hpe.ThermalConfiguration -notin $profiles) {throw 'HPE thermal configuration is not exposed or selected profile is unsupported'}
        $allowed=@($Thermal.Oem.Hpe.'ThermalConfiguration@Redfish.AllowableValues')
        if ($allowed.Count -gt 0 -and $null -ne $allowed[0] -and $selection -notin $allowed) {throw 'HPE does not advertise the selected profile'}
        $before.ThermalConfiguration=[string]$Thermal.Oem.Hpe.ThermalConfiguration;$after.ThermalConfiguration=$selection
        if ($Config.NativeMinimumEnabled) {
            $minimum=Get-HpeNumber $Config.NativeMinimum
            $original=Get-HpeNumber $Thermal.Oem.Hpe.FanPercentMinimum
            if ($null -eq $minimum -or $minimum -lt 0 -or $minimum -gt 100 -or $minimum -ne [math]::Floor($minimum) -or $null -eq $original -or $original -lt 0 -or $original -gt 100) {throw 'HPE minimum fan speed is unavailable or outside 0-100 percent'}
            $before.FanPercentMinimum=[int]$original;$after.FanPercentMinimum=[int]$minimum
        }
    } elseif ($Manufacturer -match 'Supermicro' -and $selection -ne 'FullSpeedOverride') {
        $kind='Supermicro';$path=$FanModePath
        $allowed=@($FanMode.'Mode@Redfish.AllowableValues')
        if ($selection -notin $allowed -or [string]$FanMode.Mode -notin $allowed) {throw 'Supermicro does not advertise the selected/current fan mode'}
        $before.Mode=[string]$FanMode.Mode;$after.Mode=$selection
    } elseif ($selection -eq 'FullSpeedOverride' -and $Subsystem.FansFullSpeedOverrideEnable -is [bool]) {
        $kind='RedfishOverride';$path=$SubsystemPath;$before.FansFullSpeedOverrideEnable=[bool]$Subsystem.FansFullSpeedOverrideEnable;$after.FansFullSpeedOverrideEnable=$true
    } else {throw 'No supported native fan control was detected; use Monitor only'}
    if (-not $path) {throw 'Control resource link missing'}
    return @{Kind=$kind;Path=$path;Before=$before;After=$after}
}
function Convert-NativePatch([string]$Kind,$Values) {
    $flat=@{};if ($Values -is [Collections.IDictionary]) {foreach($key in $Values.Keys){$flat[$key]=$Values[$key]}} else {foreach($property in $Values.PSObject.Properties){$flat[$property.Name]=$property.Value}}
    if ($flat.Count -eq 0) {throw 'Empty native control patch'}
    foreach($key in $flat.Keys) {
        switch ($Kind) {
            HPE {if ($key -eq 'ThermalConfiguration' -and $flat[$key] -in @('OptimalCooling','IncreasedCooling','MaximumCooling','EnhancedCooling')) {continue};if ($key -eq 'FanPercentMinimum' -and $flat[$key] -is [ValueType] -and $flat[$key] -ge 0 -and $flat[$key] -le 100 -and $flat[$key] -eq [math]::Floor($flat[$key])) {continue};throw 'Invalid HPE cooling patch'}
            Supermicro {if ($key -ne 'Mode' -or $flat[$key] -notmatch '^[A-Za-z][A-Za-z0-9]{0,39}$') {throw 'Invalid Supermicro cooling patch'}}
            DellMinimum {if($key -ne 'ThermalSettings.1.MinimumFanSpeed' -or $flat[$key] -isnot [ValueType] -or $flat[$key] -is [bool] -or ($flat[$key] -ne 255 -and ($flat[$key] -lt 0 -or $flat[$key] -gt 100)) -or $flat[$key] -ne [math]::Floor($flat[$key])){throw 'Invalid Dell minimum fan patch'}}
            RedfishOverride {if ($key -ne 'FansFullSpeedOverrideEnable' -or $flat[$key] -isnot [bool]) {throw 'Invalid Redfish cooling patch'}}
            default {throw 'Unknown cooling control type'}
        }
    }
    if ($Kind -eq 'DellMinimum') {return @{Attributes=$flat}}
    if ($Kind -eq 'HPE') {return @{Oem=@{Hpe=$flat}}};return $flat
}
function Test-NativeValues([string]$Kind,$Resource,$Values) {
    if ($Kind -eq 'DellMinimum') {$resource=$Resource.Attributes}
    if ($Kind -eq 'HPE') {$resource=$Resource.Oem.Hpe}
    if ($Values -is [Collections.IDictionary]) {$keys=@($Values.Keys)} else {$keys=@($Values.PSObject.Properties.Name)}
    foreach($key in $keys) {if ($null -eq $resource.$key -or $resource.$key -ne $Values.$key) {return $false}}
    return $true
}

function Get-DellMinimumPlan($Resource,$Requested,[string]$Path) {
    if($Resource.'@odata.type' -notmatch '^#DellAttributes\.') {throw 'Dell attribute resource is unavailable'}
    $a=$Resource.Attributes
    $original=Get-HpeNumber $a.'ThermalSettings.1.MinimumFanSpeed'
    $low=Get-HpeNumber $a.'ThermalSettings.1.MFSMinimumLimit'
    $high=Get-HpeNumber $a.'ThermalSettings.1.MFSMaximumLimit'
    $value=Get-HpeNumber $Requested
    foreach($number in @($original,$low,$high,$value)){if($null -eq $number -or $number -ne [math]::Floor($number)){throw 'Dell fan settings/limits are missing or invalid'}}
    if($low -lt 0 -or $high -gt 100 -or $low -gt $high -or $high -lt 1){throw 'Dell minimum fan limits are unavailable'}
    if($original -ne 255 -and ($original -lt 0 -or $original -gt 100)){throw 'Dell original minimum fan setting is invalid'}
    if($value -lt $low -or $value -gt $high -or ($original -ne 255 -and $value -lt $original)){throw 'Choose a fan floor within the advertised limits and no lower than the existing floor'}
    if($Path -ne '/redfish/v1/Managers/System.Embedded.1/Attributes'){throw 'Unexpected Dell attribute resource'}
    return @{Kind='DellMinimum';Path=$Path;Before=@{'ThermalSettings.1.MinimumFanSpeed'=[int]$original};After=@{'ThermalSettings.1.MinimumFanSpeed'=[int]$value}}
}
