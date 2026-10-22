#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Live,
    [switch]$LibraryOnly,
    [ValidateRange(1,2147483647)][int]$Iterations = 2147483647
)
# Default: read-only monitoring. Use -Live to enable fan writes.
# Dot-source with -LibraryOnly for offline function tests.
# =====================================================================
# Dell PowerEdge R730 CPU/GPU Fan Controller
# Made by Chris Ramsay and possibly a lil GPT
#
# Features:
#   - Manual mode only with -Live after validated telemetry
#   - Startup speed based on fresh telemetry, with a 60% safety floor
#   - GPU, CPU, exhaust and all-system-temperature fan curves
#   - Emergency cooling mode
#   - Post-load heat-soak cooldown
#   - Strict telemetry validation, fail-closed recovery and fan monitoring
#   - Fixed ASCII dashboard that refreshes in place
#   - Restores Dell automatic fan control when stopped
# =====================================================================

# -----------------------------
# Programs and iDRAC connection
# -----------------------------

$IpmiExe = $(if($env:THERMAL_OPS_IPMITOOL){$env:THERMAL_OPS_IPMITOOL}else{'ipmitool.exe'})

$IdracHost = $env:THERMAL_OPS_IDRAC_HOST
$IdracUser = $(if($env:THERMAL_OPS_IDRAC_USER){$env:THERMAL_OPS_IDRAC_USER}else{'root'})
$IdracPass = $env:THERMAL_OPS_IDRAC_PASSWORD

$NvidiaSmi = "nvidia-smi"

# -----------------------------
# General fan settings
# -----------------------------

$PollSeconds = 2


$MinFan      = 10
$MaxFan      = 100
$FailSafeFan = 60

$LastFan       = -1
$EmergencyMode = $false

# -----------------------------
# Emergency thresholds
# -----------------------------

$GpuEmergencyOn  = 83
$GpuEmergencyOff = 72

$CpuEmergencyOn  = 85
$CpuEmergencyOff = 75

$ExhaustEmergencyOn  = 60
$ExhaustEmergencyOff = 50

# Any additional IPMI temperature sensor not already classified as
# CPU, inlet or exhaust is treated as a system temperature.
$SystemEmergencyOn  = 85
$SystemEmergencyOff = 75

# -----------------------------
# Post-load cooldown
# -----------------------------

$GpuLoadUtilThreshold  = 65
$GpuLoadPowerThreshold = 100

$CooldownSeconds    = 120
$CooldownFanPercent = 55

$LastGpuLoadTime = $null

# -----------------------------
# Dashboard state
# -----------------------------

$ControllerStartTime = Get-Date
$LastError           = "None"

# =====================================================================
# IPMI functions
# =====================================================================

# =====================================================================
# Fan curves
# =====================================================================

function Get-GpuFanTarget {
    param([int]$Temperature)

    if     ($Temperature -le 40) { return 10 }
    elseif ($Temperature -le 45) { return 14 }
    elseif ($Temperature -le 55) { return 24 }
    elseif ($Temperature -le 62) { return 28 }
    elseif ($Temperature -le 68) { return 45 }
    elseif ($Temperature -le 74) { return 85 }
    else                         { return 100 }
}

function Get-CpuFanTarget {
    param([int]$Temperature)

    if     ($Temperature -le 40) { return 10 }
    elseif ($Temperature -le 45) { return 14 }
    elseif ($Temperature -le 55) { return 22 }
    elseif ($Temperature -le 62) { return 26 }
    elseif ($Temperature -le 70) { return 32 }
    elseif ($Temperature -le 78) { return 40 }
    elseif ($Temperature -le 85) { return 55 }
    else                         { return 100 }
}

function Get-ExhaustFanTarget {
    param([int]$Temperature)

    if     ($Temperature -le 34) { return 10 }
    elseif ($Temperature -le 38) { return 16 }
    elseif ($Temperature -le 42) { return 24 }
    elseif ($Temperature -le 46) { return 30 }
    elseif ($Temperature -le 50) { return 36 }
    elseif ($Temperature -le 55) { return 44 }
    else                         { return 100 }
}

function Get-SystemFanTarget {
    param([int]$Temperature)

    if     ($Temperature -le 40) { return 10 }
    elseif ($Temperature -le 50) { return 18 }
    elseif ($Temperature -le 60) { return 26 }
    elseif ($Temperature -le 70) { return 36 }
    elseif ($Temperature -le 78) { return 50 }
    elseif ($Temperature -le 84) { return 70 }
    else                         { return 100 }
}

function Limit-Number {
    param(
        [int]$Value,
        [int]$Minimum,
        [int]$Maximum
    )

    return [math]::Max($Minimum, [math]::Min($Maximum, $Value))
}

# =====================================================================
# Formatting and dashboard functions
# =====================================================================

function Format-Value {
    param(
        $Value,
        [string]$Suffix = ""
    )

    if ($null -eq $Value) {
        return "N/A"
    }

    return "$Value$Suffix"
}

function Format-Uptime {
    param([TimeSpan]$Uptime)

    return "{0:00}d {1:00}:{2:00}:{3:00}" -f `
        [math]::Floor($Uptime.TotalDays),
        $Uptime.Hours,
        $Uptime.Minutes,
        $Uptime.Seconds
}

function Fit-Text {
    param(
        [AllowNull()]
        [string]$Text,
        [int]$Width
    )

    if ($null -eq $Text) {
        $Text = ""
    }

    if ($Text.Length -gt $Width) {
        if ($Width -ge 3) {
            return $Text.Substring(0, $Width - 3) + "..."
        }

        return $Text.Substring(0, $Width)
    }

    return $Text.PadRight($Width)
}

function Get-FanValues {
    param($Fans)

    $Result = [ordered]@{}

    foreach ($Number in 1..6) {
        $FanName = "Fan$Number"

        $Sensor = @(
            $Fans |
            Where-Object { $_.Name -eq $FanName }
        ) | Select-Object -First 1

        $Result[$FanName] = if ($null -ne $Sensor) {
            $Sensor.Value
        }
        else {
            $null
        }
    }

    return $Result
}

function Write-Dashboard {
    param(
        $Ipmi,
        $Gpu,
        [int]$TargetFan,
        [string]$Mode,
        [string]$Action,
        [int]$CooldownRemaining,
        [string]$ErrorMessage
    )

    $InnerWidth = 70
    $Border     = "+" + ("-" * $InnerWidth) + "+"
    $FanValues = Get-FanValues -Fans $Ipmi.Fans
    $Uptime    = (Get-Date) - $ControllerStartTime

    $CooldownText = if ($CooldownRemaining -gt 0) {
        "$CooldownRemaining seconds"
    }
    else {
        "Inactive"
    }

    $Lines = @(
        $Border
        "|" + (Fit-Text "        DELL POWEREDGE R730 THERMAL CONTROLLER" $InnerWidth) + "|"
        "|" + (Fit-Text "        Chris Ramsay and possibly a lil GPT" $InnerWidth) + "|"
        $Border
        "|" + (Fit-Text " iDRAC: $IdracHost               Poll interval: $PollSeconds seconds" $InnerWidth) + "|"
        "|" + (Fit-Text " Controller uptime: $(Format-Uptime $Uptime)" $InnerWidth) + "|"
        $Border
        "|" + (Fit-Text " MODE: $Mode" $InnerWidth) + "|"
        "|" + (Fit-Text " ACTION: $Action" $InnerWidth) + "|"
        "|" + (Fit-Text " FAN COMMAND: $TargetFan%            COOLDOWN: $CooldownText" $InnerWidth) + "|"
        $Border
        "|" + (Fit-Text " GPU temperature : $(Format-Value $Gpu.Temp ' C')" $InnerWidth) + "|"
        "|" + (Fit-Text " GPU utilisation : $(Format-Value $Gpu.Util ' %')" $InnerWidth) + "|"
        "|" + (Fit-Text " GPU power       : $(Format-Value $Gpu.Power ' W')" $InnerWidth) + "|"
        "|" + (Fit-Text " CPU maximum     : $(Format-Value $Ipmi.CpuMax ' C')" $InnerWidth) + "|"
        "|" + (Fit-Text " Inlet           : $(Format-Value $Ipmi.Inlet ' C')" $InnerWidth) + "|"
        "|" + (Fit-Text " Exhaust         : $(Format-Value $Ipmi.Exhaust ' C')" $InnerWidth) + "|"
        "|" + (Fit-Text " Hottest system  : $(Format-Value $Ipmi.SystemMax ' C') [$($Ipmi.HottestSystemSensor)]" $InnerWidth) + "|"
        "|" + (Fit-Text " System power    : $(Format-Value $Ipmi.Watts ' W')" $InnerWidth) + "|"
        $Border
        "|" + (Fit-Text " Fan1: $(Format-Value $FanValues.Fan1 ' RPM')    Fan2: $(Format-Value $FanValues.Fan2 ' RPM')" $InnerWidth) + "|"
        "|" + (Fit-Text " Fan3: $(Format-Value $FanValues.Fan3 ' RPM')    Fan4: $(Format-Value $FanValues.Fan4 ' RPM')" $InnerWidth) + "|"
        "|" + (Fit-Text " Fan5: $(Format-Value $FanValues.Fan5 ' RPM')    Fan6: $(Format-Value $FanValues.Fan6 ' RPM')" $InnerWidth) + "|"
        $Border
        "|" + (Fit-Text " Last error: $ErrorMessage" $InnerWidth) + "|"
        "|" + (Fit-Text " Press Ctrl+C to stop and restore Dell automatic fan control." $InnerWidth) + "|"
        $Border
    )

    try {
        [Console]::SetCursorPosition(0, 0)
    }
    catch {
        Clear-Host
    }

    foreach ($Line in $Lines) {
        Write-Host $Line
    }
}

function New-EmptyIpmiTelemetry {
    return [PSCustomObject]@{
        Fans    = @()
        CpuMax  = $null
        Inlet   = $null
        Exhaust             = $null
        Watts               = $null
        SystemMax           = $null
        HottestSystemSensor = "N/A"
    }
}

function New-EmptyGpuTelemetry {
    return [PSCustomObject]@{
        Temp  = $null
        Util  = $null
        Power = $null
    }
}


# Revised I/O and controller. Original R730 curves and thermal thresholds above.
$CommandTimeoutSeconds = 30
$TelemetryBudgetSeconds = 35
$DecreaseHoldSeconds = 20
$DecreaseStep = 3
$RefreshSeconds = 30
$ResponseTimeoutSeconds = 30
$Clock = [Diagnostics.Stopwatch]::StartNew()
$ManualAttempted = $false
$LastWriteTime = -1000.0
$LowerSince = $null
$ResponseCheck = $null
$ExpectedTemps = @{}
$ExpectedGpuCount = 0
$Mutex = $null
$OwnMutex = $false

function Invoke-CheckedProcess {
    param([string]$File, [string[]]$Arguments)
    # Arguments below are fixed tokens or validated connection fields; never shell code.
    foreach ($arg in $Arguments) {
        if ($arg -match '["\r\n]') { throw 'Invalid command argument' }
    }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = (($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = New-Object Diagnostics.Process
    $p.StartInfo = $psi
    try {
        if (-not $p.Start()) { throw 'Command could not start' }
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($CommandTimeoutSeconds * 1000)) {
            try { $p.Kill() } catch {}
            throw "Command timed out after $CommandTimeoutSeconds seconds"
        }
        $output = $outTask.GetAwaiter().GetResult()
        $null = $errTask.GetAwaiter().GetResult()
        if ($p.ExitCode -ne 0) { throw "External command failed (exit $($p.ExitCode))" }
        return $output
    } finally { $p.Dispose() }
}

function Invoke-Ipmi {
    param([string[]]$Arguments)
    Invoke-CheckedProcess $IpmiExe (@('-I','lanplus','-H',$IdracHost,'-U',$IdracUser,'-P',$IdracPass) + $Arguments)
}
function Invoke-IpmiRaw {
    param([string[]]$Arguments)
    if ($Live) { $null = Invoke-Ipmi (@('raw') + $Arguments) }
}
function Set-ManualFanMode { Invoke-IpmiRaw @('0x30','0x30','0x01','0x00') }
function Set-AutoFanMode { Invoke-IpmiRaw @('0x30','0x30','0x01','0x01') }
function Set-FanPercent {
    param([ValidateRange(10,100)][int]$Percent)
    Invoke-IpmiRaw @('0x30','0x30','0x02','0xff',('0x{0:X2}' -f $Percent))
}
function Convert-Number {
    param([string]$Text, [double]$Minimum, [double]$Maximum)
    $n = 0.0
    if (-not [double]::TryParse($Text.Trim(), [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$n) -or
        [double]::IsNaN($n) -or [double]::IsInfinity($n) -or $n -lt $Minimum -or $n -gt $Maximum) {
        throw 'Missing or invalid telemetry number'
    }
    return $n
}
function Convert-IpmiTelemetry {
    param([string]$Raw)
    $temps = @(); $fans = @(); $watts = $null
    foreach ($line in ($Raw -split '\r?\n')) {
        $p = @($line -split '\|')
        if ($p.Count -lt 3) { continue }
        $name=$p[0].Trim(); $unit=$p[2].Trim(); $value=$p[1].Trim()
        if ($unit -notin @('degrees C','RPM','Watts')) { continue }
        if ($value -match '^(na|n/a|)$') { continue }
        $max = if ($unit -eq 'degrees C') { 150 } else { 100000 }
        $min = if ($unit -eq 'degrees C') { -20 } else { 0 }
        $n = Convert-Number $value $min $max
        if ($p.Count -gt 3 -and $p[3].Trim() -notin @('ok','ns')) {
            throw "Sensor reports unhealthy status: $name"
        }
        $sensor = [pscustomobject]@{Name=$name; Value=$n}
        switch ($unit) {
            'degrees C' { $temps += $sensor }
            'RPM' { $fans += $sensor }
            'Watts' { if ($name -eq 'Pwr Consumption') { $watts=$n } }
        }
    }
    $cpu=@($temps | Where-Object Name -eq 'Temp')
    $inlet=@($temps | Where-Object Name -eq 'Inlet Temp')
    $exhaust=@($temps | Where-Object Name -eq 'Exhaust Temp')
    if ($cpu.Count -ne 2 -or $inlet.Count -ne 1 -or $exhaust.Count -ne 1) {
        throw 'Required R730 telemetry missing: two Temp CPUs, inlet and exhaust required'
    }
    foreach ($i in 1..6) {
        $f=@($fans | Where-Object Name -eq "Fan$i")
        if ($f.Count -ne 1 -or $f[0].Value -le 0) { throw "Fan$i missing or stalled" }
    }
    $system=@($temps | Where-Object { $_.Name -notin @('Temp','Inlet Temp','Exhaust Temp') })
    $hot=$system | Sort-Object Value -Descending | Select-Object -First 1
    [pscustomobject]@{
        Temps=$temps; Fans=$fans; Watts=$watts; CpuTemps=$cpu
        CpuMax=($cpu | Measure-Object Value -Maximum).Maximum
        Inlet=$inlet[0].Value; Exhaust=$exhaust[0].Value
        SystemTemps=$system; SystemMax=$(if ($hot) {$hot.Value} else {$null})
        HottestSystemSensor=$(if ($hot) {$hot.Name} else {'N/A'})
    }
}
function Convert-GpuTelemetry {
    param([string]$Raw)
    $gpus=@(foreach ($line in ($Raw -split '\r?\n')) {
        if (-not $line.Trim()) { continue }
        $p=@($line -split ',')
        if ($p.Count -ne 3) { throw 'Unexpected GPU telemetry columns' }
        [pscustomobject]@{Temp=(Convert-Number $p[0] 0 150)
            Util=(Convert-Number $p[1] 0 100); Power=(Convert-Number $p[2] 0 2000)}
    })
    if ($gpus.Count -eq 0) { throw 'No GPU telemetry returned' }
    # Independent maxima ensure any GPU can trigger cooling or the load hold.
    [pscustomobject]@{Temp=($gpus | Measure-Object Temp -Maximum).Maximum
        Util=($gpus | Measure-Object Util -Maximum).Maximum
        Power=($gpus | Measure-Object Power -Maximum).Maximum; Count=$gpus.Count}
}
function Get-IpmiTelemetry { Convert-IpmiTelemetry (Invoke-Ipmi @('sensor')) }
function Get-GpuTelemetry {
    Convert-GpuTelemetry (Invoke-CheckedProcess $NvidiaSmi @('--query-gpu=temperature.gpu,utilization.gpu,power.draw','--format=csv,noheader,nounits'))
}
function Get-ControlTarget {
    param($Ipmi, $Gpu, [double]$Seconds)
    if ($Gpu.Util -ge $GpuLoadUtilThreshold -or $Gpu.Power -ge $GpuLoadPowerThreshold) {
        $script:LastGpuLoadTime = $Seconds
    }
    $script:CooldownRemaining = 0
    if ($null -ne $LastGpuLoadTime) {
        $script:CooldownRemaining = [int][math]::Max(0,[math]::Ceiling($CooldownSeconds-($Seconds-$LastGpuLoadTime)))
    }
    if ($Gpu.Temp -ge $GpuEmergencyOn -or $Ipmi.CpuMax -ge $CpuEmergencyOn -or
        $Ipmi.Exhaust -ge $ExhaustEmergencyOn -or
        ($null -ne $Ipmi.SystemMax -and $Ipmi.SystemMax -ge $SystemEmergencyOn)) {
        $script:EmergencyMode=$true
    }
    if ($EmergencyMode -and $Gpu.Temp -lt $GpuEmergencyOff -and $Ipmi.CpuMax -lt $CpuEmergencyOff -and
        $Ipmi.Exhaust -lt $ExhaustEmergencyOff -and ($null -eq $Ipmi.SystemMax -or $Ipmi.SystemMax -lt $SystemEmergencyOff)) {
        $script:EmergencyMode=$false
    }
    if ($EmergencyMode) { return 100 }
    $targets=@((Get-GpuFanTarget $Gpu.Temp), (Get-CpuFanTarget $Ipmi.CpuMax), (Get-ExhaustFanTarget $Ipmi.Exhaust))
    if ($null -ne $Ipmi.SystemMax) { $targets += Get-SystemFanTarget $Ipmi.SystemMax }
    if ($CooldownRemaining -gt 0) { $targets += $CooldownFanPercent }
    return [int](($targets | Measure-Object -Maximum).Maximum)
}
function Get-SmoothedTarget {
    param([int]$Target,[int]$Previous,[double]$Seconds)
    if ($Previous -lt 0 -or $Target -ge $Previous) {
        $script:LowerSince=$null
        return $Target
    }
    if ($null -eq $LowerSince) { $script:LowerSince=$Seconds }
    if ($Seconds-$LowerSince -lt $DecreaseHoldSeconds) { return $Previous }
    $script:LowerSince=$Seconds
    return [int][math]::Max($Target,$Previous-$DecreaseStep)
}
function Assert-SensorInventory {
    param($Ipmi,$Gpu)
    $counts=@{}
    foreach ($t in $Ipmi.Temps) { $counts[$t.Name]++ }
    foreach ($name in $ExpectedTemps.Keys) {
        if ($counts[$name] -ne $ExpectedTemps[$name]) { throw "Temperature sensor disappeared: $name" }
    }
    foreach ($name in $counts.Keys) { $script:ExpectedTemps[$name]=$counts[$name] }
    if ($ExpectedGpuCount -gt 0 -and $Gpu.Count -ne $ExpectedGpuCount) { throw 'GPU count changed' }
    $script:ExpectedGpuCount=$Gpu.Count
}
function Test-FanResponse {
    param($Ipmi,[double]$Seconds)
    if ($null -eq $ResponseCheck -or -not $Live) { return }
    if ($Seconds-$ResponseCheck.Time -lt $ResponseTimeoutSeconds) { return }
    foreach ($before in $ResponseCheck.Fans) {
        $after=$Ipmi.Fans | Where-Object Name -eq $before.Name
        if ($after.Value -lt $before.Value*1.05) { throw "No RPM rise after substantial fan increase: $($before.Name)" }
    }
    $script:ResponseCheck=$null
}

. (Join-Path $PSScriptRoot 'SystemIdentity.ps1')
. (Join-Path $PSScriptRoot 'DellCompatibility.ps1')
if ($LibraryOnly) { return }
if ([string]::IsNullOrWhiteSpace($IdracHost)) { throw 'Set THERMAL_OPS_IDRAC_HOST before starting.' }
if ([string]::IsNullOrEmpty($IdracPass)) {
    $secure=Read-Host 'iDRAC password' -AsSecureString
    $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $IdracPass=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer);$secure.Dispose() }
}
try {
    $IpmiExe=(Get-Command $IpmiExe -CommandType Application -ErrorAction Stop).Source
    $NvidiaSmi=(Get-Command $NvidiaSmi -CommandType Application -ErrorAction Stop).Source
    # One controller per iDRAC across Windows sessions, including monitor sessions.
    $key=$IdracHost -replace '[^a-zA-Z0-9.-]','_'
    $Mutex=New-Object Threading.Mutex($false,"Global\R730FanController_$key")
    try { $OwnMutex=$Mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $OwnMutex=$true }
    if (-not $OwnMutex) { throw 'Another controller instance is running for this iDRAC' }
    # Confirm model before issuing R730-specific raw commands.
    # FRU inventory is slower than routine telemetry on this iDRAC.
    $routineTimeout=$CommandTimeoutSeconds
    try {
        $CommandTimeoutSeconds=25
        $model=Invoke-Ipmi @('fru','print')
    } finally { $CommandTimeoutSeconds=$routineTimeout }
    $identity=Convert-TargetIdentity $model
    if($identity.Model -ne 'PowerEdge R730'){throw 'Console curves require a PowerEdge R730; use the GUI for other server monitoring'}
    if($Live){$compatibility=Get-DellCompatibility $identity (Invoke-Ipmi @('mc','info'));if(-not $compatibility.ManualControlAllowed){throw $compatibility.Reason}}
    Clear-Host
    try { [Console]::CursorVisible=$false } catch {}
    for ($iteration=0; $iteration -lt $Iterations; $iteration++) {
        $sampleStart=$Clock.Elapsed.TotalSeconds
        $Ipmi=Get-IpmiTelemetry
        $Gpu=Get-GpuTelemetry
        $seconds=$Clock.Elapsed.TotalSeconds
        if ($seconds-$sampleStart -gt $TelemetryBudgetSeconds) { throw 'Telemetry collection exceeded freshness budget' }
        Assert-SensorInventory $Ipmi $Gpu
        Test-FanResponse $Ipmi $seconds
        $target=Get-ControlTarget $Ipmi $Gpu $seconds
        if ($iteration -eq 0) {
            # Fresh telemetry determines startup; never blindly command 15%.
            $target=[math]::Max($FailSafeFan,$target)
            if ($Live) { $ManualAttempted=$true; Set-ManualFanMode }
        }
        $target=Get-SmoothedTarget $target $LastFan $seconds
        if ($target -ne $LastFan -or $seconds-$LastWriteTime -ge $RefreshSeconds) {
            Set-FanPercent $target
            if ($LastFan -ge 0 -and $target-$LastFan -ge 10 -and $null -eq $ResponseCheck) {
                $ResponseCheck=[pscustomobject]@{Time=$seconds; Fans=$Ipmi.Fans}
            }
            $LastFan=$target
            $LastWriteTime=$seconds
        }
        $mode=if (-not $Live) {'MONITOR - NO WRITES'} elseif ($EmergencyMode) {'EMERGENCY'} elseif ($Gpu.Util -ge $GpuLoadUtilThreshold -or $Gpu.Power -ge $GpuLoadPowerThreshold) {'GPU LOAD'} elseif ($CooldownRemaining -gt 0) {'COOLDOWN'} else {'NORMAL'}
        $action=if ($Live) {'Command accepted; RPM rise monitored on increases >=10 points'} else {'Read-only: displayed command is proposed'}
        Write-Dashboard $Ipmi $Gpu $LastFan $mode $action $CooldownRemaining 'None'
        # Keep polling during startup; no blind settle sleep.
        if ($iteration+1 -lt $Iterations) { Start-Sleep -Seconds $PollSeconds }
    }
} catch {
    $failure=$_.Exception.Message
    if ($ManualAttempted) {
        # Never lower an emergency/high command on telemetry failure.
        try { Set-FanPercent 100; $LastFan=100 } catch { Write-Warning 'Emergency 100% command failed.' }
    }
    Write-Warning "Controller stopped: $failure"
    throw
} finally {
    if ($ManualAttempted) {
        $restored=$false
        foreach ($attempt in 1..3) {
            try { Set-AutoFanMode; $restored=$true; break } catch { Write-Warning "Automatic mode restore attempt $attempt failed." }
        }
        if ($restored) { Write-Host 'Dell automatic fan control command accepted.' }
        else { Write-Warning 'AUTOMATIC RESTORE FAILED. Check iDRAC and restore cooling control manually NOW.' }
    }
    try { [Console]::CursorVisible=$true } catch {}
    if ($OwnMutex) { $Mutex.ReleaseMutex() }
    if ($null -ne $Mutex) { $Mutex.Dispose() }
}
