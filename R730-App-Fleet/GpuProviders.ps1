# Windows GPU telemetry adapters. This file sends no fan or GPU-setting commands.
$GpuProvider='Auto'
$SelectedGpuProviders=@()
$ExpectedGpuIds=@()
$MonitorExcludeNvidia=$false

function Convert-OptionalGpuNumber {
    param($Text,[double]$Maximum)
    if ($null -eq $Text -or ([string]$Text).Trim() -match '^(N/A|\[N/A\]|Not Supported|\[Not Supported\]|)$') { return $null }
    Convert-Number ([string]$Text) 0 $Maximum
}
function Convert-NvidiaCards {
    param([string]$Raw)
    $cards=@(foreach ($row in ($Raw | ConvertFrom-Csv -Header Id,Name,Bus,Temp,Util,Power)) {
        $id=([string]$row.Id).Trim();$name=([string]$row.Name).Trim()
        if ($id -notmatch '^GPU-[A-Za-z0-9-]+$' -or -not $name) { throw 'NVIDIA returned no usable GPU identity/name' }
        $temp=Convert-Number ([string]$row.Temp) 0 150
        [pscustomobject]@{Id=('NVIDIA:'+$id);Name=$name;Vendor='NVIDIA';Provider='NVIDIA'
            Temp=$temp;Util=(Convert-OptionalGpuNumber $row.Util 100)
            Power=(Convert-OptionalGpuNumber $row.Power 2500);Bus=([string]$row.Bus).Trim()}
    })
    if ($cards.Count -eq 0) { throw 'NVIDIA returned no GPU readings' }
    return $cards
}
function Convert-MonitorCards {
    param($Hardware,$Sensors,[string]$Provider,[switch]$ExcludeNvidia)
    $cards=@(foreach ($gpu in @($Hardware | Where-Object { $_.HardwareType -match '^Gpu(Nvidia|Amd|Ati|Intel)$' -and (-not $ExcludeNvidia -or $_.HardwareType -ne 'GpuNvidia') })) {
        $id=[string]$gpu.Identifier
        if (-not $id) { throw 'Hardware monitor returned a GPU without identity' }
        $own=@($Sensors | Where-Object { $_.Parent -eq $id })
        $core=@($own | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -match '^(GPU Core|GPU Temperature|GPU|Core)$' })
        if ($core.Count -ne 1 -or $null -eq $core[0].Value) { throw "Required core temperature missing/ambiguous: $($gpu.Name)" }
        $temp=Convert-Number ([string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0}',$core[0].Value)) 0 150
        $load=@($own | Where-Object { $_.SensorType -eq 'Load' -and $_.Name -match '^(GPU Core|GPU D3D 3D|GPU Total|GPU)$' })
        $power=@($own | Where-Object { $_.SensorType -eq 'Power' -and $_.Name -match '^(GPU Package|GPU Board|GPU Total|GPU Power|GPU)$' })
        $util=$null;$watts=$null
        if ($load.Count) { $util=(@($load | ForEach-Object { Convert-OptionalGpuNumber ([string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0}',$_.Value)) 100 }) | Measure-Object -Maximum).Maximum }
        if ($power.Count) { $watts=(@($power | ForEach-Object { Convert-OptionalGpuNumber ([string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0}',$_.Value)) 2500 }) | Measure-Object -Maximum).Maximum }
        $vendor=switch -Regex ($gpu.HardwareType) {'Nvidia' {'NVIDIA';break} 'Amd|Ati' {'AMD';break} 'Intel' {'Intel';break}}
        [pscustomobject]@{Id=($Provider+':'+$id+'#'+[string]$gpu.Name);Name=[string]$gpu.Name;Vendor=$vendor;Provider=$Provider;Temp=$temp;Util=$util;Power=$watts;Bus=$null}
    })
    if (-not $cards.Count) { throw "$Provider exposes no supported GPU core temperatures" }
    return $cards
}
function Get-MonitorCards {
    param([string]$Provider,[switch]$ExcludeNvidia)
    $namespace='root\'+$Provider
    $hardware=@(Get-CimInstance -Namespace $namespace -ClassName Hardware -OperationTimeoutSec 4 -ErrorAction Stop)
    $sensors=@(Get-CimInstance -Namespace $namespace -ClassName Sensor -OperationTimeoutSec 4 -ErrorAction Stop)
    Convert-MonitorCards $hardware $sensors $Provider -ExcludeNvidia:$ExcludeNvidia
}
function Get-NvidiaCards {
    $exe=(Get-Command $NvidiaSmi -CommandType Application -ErrorAction Stop).Source
    Convert-NvidiaCards (Invoke-CheckedProcess $exe @('--query-gpu=uuid,name,pci.bus_id,temperature.gpu,utilization.gpu,power.draw','--format=csv,noheader,nounits'))
}
function Get-PciGpuCounts {
    $counts=@{NVIDIA=0;AMD=0;Intel=0}
    foreach ($adapter in @(Get-CimInstance -ClassName Win32_VideoController -OperationTimeoutSec 4 -ErrorAction Stop)) {
        switch -Regex ([string]$adapter.PNPDeviceID) {
            '^PCI\\VEN_10DE' { $counts.NVIDIA++;break }
            '^PCI\\VEN_1002' { $counts.AMD++;break }
            '^PCI\\VEN_8086' { $counts.Intel++;break }
        }
    }
    return $counts
}
function Assert-GpuCoverage {
    param($Cards,$Counts)
    foreach ($vendor in @('NVIDIA','AMD','Intel')) {
        $found=@($Cards | Where-Object Vendor -eq $vendor).Count
        if ($found -lt $Counts[$vendor]) { throw "$vendor adapter detected without temperature coverage. Start LibreHardwareMonitor with working WMI output, or check its driver/tool configuration." }
    }
}
function Assert-GpuIdentities {
    param($Cards)
    $ids=@($Cards.Id | Sort-Object)
    if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { throw 'Duplicate GPU identities returned' }
    if ($ExpectedGpuIds.Count -and @(Compare-Object $ExpectedGpuIds $ids).Count) { throw 'GPU identity set changed; restart to enrol the current cards' }
    $script:ExpectedGpuIds=$ids
}
function Merge-GpuCards {
    param($Cards)
    if (-not @($Cards).Count) { throw 'No usable GPU temperature telemetry' }
    Assert-GpuIdentities $Cards
    $missing=@($Cards | Where-Object { $null -eq $_.Util -or $null -eq $_.Power })
    [pscustomobject]@{Temp=($Cards | Measure-Object Temp -Maximum).Maximum
        Util=($Cards | Where-Object { $null -ne $_.Util } | Measure-Object Util -Maximum).Maximum
        Power=($Cards | Where-Object { $null -ne $_.Power } | Measure-Object Power -Maximum).Maximum
        Count=@($Cards).Count;Cards=@($Cards);OptionalMissing=($missing.Count -gt 0)
        Warning=$(if($missing.Count){'Load/power unavailable: conservative 55% minimum'}else{''})}
}
function Get-GpuSafeTarget {
    param($Ipmi,$Gpu,[double]$Seconds)
    if ($Gpu.OptionalMissing) { $script:LastGpuLoadTime=$Seconds }
    $target=Get-ControlTarget $Ipmi $Gpu $Seconds
    if ($Gpu.OptionalMissing) { $target=[math]::Max($CooldownFanPercent,$target) }
    return [int]$target
}
function Get-GpuTelemetry {
    $cards=@()
    $counts=$null
    if ($GpuProvider -eq 'Auto') { $counts=Get-PciGpuCounts }
    if (-not $SelectedGpuProviders.Count) {
        if ($GpuProvider -ne 'Auto') { $script:SelectedGpuProviders=@($GpuProvider) }
        else {
            # Use native NVIDIA data when all supported PCI adapters are NVIDIA.
            $native=Get-Command $NvidiaSmi -CommandType Application -ErrorAction SilentlyContinue
            if ($native -and $counts.AMD -eq 0 -and $counts.Intel -eq 0) { $script:SelectedGpuProviders=@('NVIDIA') }
            else {
                $nativeCards=@()
                $useNative=($null -ne $native -and $counts.NVIDIA -gt 0)
                if ($useNative) { $nativeCards=@(Get-NvidiaCards) }
                foreach ($candidate in @('LibreHardwareMonitor','OpenHardwareMonitor')) {
                    try {
                        $probe=@($nativeCards)+@(Get-MonitorCards $candidate -ExcludeNvidia:$useNative)
                        Assert-GpuCoverage $probe $counts
                        $cards=$probe
                        $script:MonitorExcludeNvidia=$useNative
                        $script:SelectedGpuProviders=@($candidate)
                        if ($useNative) { $script:SelectedGpuProviders=@('NVIDIA',$candidate) }
                        break
                    } catch { $diagnostic=$_.Exception.Message }
                }
                if (-not $SelectedGpuProviders.Count) { throw "No provider covers all detected GPU adapters. $diagnostic" }
            }
        }
    }
    if (-not $cards.Count) {
        foreach ($provider in $SelectedGpuProviders) {
            if ($provider -eq 'NVIDIA') { $cards+=@(Get-NvidiaCards) }
            else { $cards+=@(Get-MonitorCards $provider -ExcludeNvidia:$MonitorExcludeNvidia) }
        }
    }
    if ($counts) { Assert-GpuCoverage $cards $counts }
    # Provider selection is sticky for this run; never silently switch sources
    # after a read failure, because that could hide a disappeared/hot card.
    Merge-GpuCards $cards
}
