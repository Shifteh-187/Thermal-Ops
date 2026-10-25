#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Live,
    [switch]$LibraryOnly,
    [switch]$Smart,
    [string]$SettingsPath,
    [string]$StatusPath,
    [string]$StopPath,
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

$IpmiExe = $null

$IdracHost = $null
$IdracUser = $null
$IdracPass = $null

$NvidiaSmi = $null

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
$RequestedLive=[bool]$Live
$failure=$null
$ExitReason='Running'
$RetryAllowed=$false
$preflight=0
$DellRecoveryPath=$null
$Discovery=@()
$LastWriteTime = -1000.0
$LowerSince = $null
$ResponseCheck = $null
$ExpectedTemps = @{}
$ExpectedGpuCount = 0
$Mutex = $null
$OwnMutex = $false
$PhysicalMutex = $null
$OwnPhysicalMutex = $false

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
    if ($Live) { if(-not $TargetIdentity.ManualControlAllowed){throw 'Raw fan control denied by hardware compatibility policy'}; $null = Invoke-Ipmi (@('raw') + $Arguments) }
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
        $sensor = [pscustomobject]@{Name=$name; Value=$n;Units=$unit;Status=$(if($p.Count -gt 3){$p[3].Trim()}else{'Unknown'})}
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
        Temps=$temps; Fans=$fans; Watts=$watts; CpuTemps=$cpu;ReportedHealth='TELEMETRY OK'
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


function Get-ControllerExitReason([string]$Message) {
    if($Message -match 'No RPM rise|Fan\d missing or stalled|Sensor reports unhealthy'){return 'HardwareSafetyFault'}
    if($Message -match 'Custom curve sensor unavailable|Required R730 telemetry missing|Temperature sensor disappeared|GPU count changed|No GPU telemetry returned|Unexpected GPU telemetry columns|Missing or invalid telemetry number|Telemetry collection exceeded|Server identity read unavailable'){return 'TelemetryUnavailable'}
    if($Message -match '^Command timed out|^External command failed'){return 'ConnectionOrCommandFailure'}
    return 'ConfigurationOrUnexpectedFault'
}
function Write-AppStatus {
    param([string]$State, [string]$Message, $Ipmi=$null, $Gpu=$null)
    if (-not $StatusPath) { return }
    $data=[ordered]@{Time=(Get-Date -Format o); State=$State; Message=$Message;
        ExitReason=$ExitReason; FailureMessage=$failure; RetryAllowed=$RetryAllowed; RequestedLive=$RequestedLive;
        HardwareDiscovery=@($Discovery);FanCurveMode=$(if($settings -and $settings.FanCurveMode){[string]$settings.FanCurveMode}elseif($Smart){'Smart'}else{'Original'});
        StopRequested=[bool]($StopPath -and (Test-Path -LiteralPath $StopPath));
        Live=[bool]$Live; ManagementProvider='Dell'; Smart=[bool]$Smart; Fan=$LastFan; Ipmi=$Ipmi; Gpu=$Gpu;
        ProfileName=$ProfileName; GpuMode=$GpuMode; TargetIdentity=$TargetIdentity; IdracHost=$IdracHost; CooldownRemaining=$CooldownRemaining; UptimeSeconds=[int]$Clock.Elapsed.TotalSeconds}
    $json=$data | ConvertTo-Json -Depth 8 -Compress
    # Keep UI/logging failures from interrupting cooling or restoration.
    try {
        [IO.File]::WriteAllText($StatusPath+'.tmp',$json)
        Move-Item -LiteralPath ($StatusPath+'.tmp') -Destination $StatusPath -Force -ErrorAction Stop
    } catch {}
}
if ($Smart) { . (Join-Path $PSScriptRoot 'R730-SmartControl.ps1') }

. (Join-Path $PSScriptRoot 'GpuProviders.ps1')
. (Join-Path $PSScriptRoot 'SystemIdentity.ps1')
. (Join-Path $PSScriptRoot 'DellCompatibility.ps1')
. (Join-Path $PSScriptRoot 'HardwareDiscovery.ps1')
. (Join-Path $PSScriptRoot 'CustomFanCurves.ps1')
if ($LibraryOnly) { return }
try {
    Write-AppStatus 'Starting' 'Checking configuration and server'
    if (-not $SettingsPath) { throw 'Settings file required' }
    $settings=Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    try{Assert-CustomFanSettings $settings}catch{throw 'Invalid custom fan settings; check selected sensors, mode, points and percentage bounds'}
    if($settings.FanCurveMode){$Smart=[switch]($settings.FanCurveMode -eq 'Smart');if($Smart){. (Join-Path $PSScriptRoot 'R730-SmartControl.ps1')}}
    foreach ($name in @('IpmiExe','IdracHost','IdracUser')) {
        if (-not $settings.$name) { throw "Missing setting: $name" }
        Set-Variable -Name $name -Value ([string]$settings.$name) -Scope Script
    }
    $NvidiaSmi=if ($settings.NvidiaSmi) { [string]$settings.NvidiaSmi } else { 'nvidia-smi' }
    if ($settings.GpuProvider) {
        if ($settings.GpuProvider -notin @('Auto','NVIDIA','LibreHardwareMonitor','OpenHardwareMonitor')) { throw 'Unknown GPU provider setting' }
        $GpuProvider=[string]$settings.GpuProvider
    }
    $ProfileName=[string]$settings.ProfileName
    $GpuMode=[string]$settings.GpuMode
    if ($Live -and ($GpuMode -notin @('Local','ServerOnly') -or $settings.GpuSourceConfirmed -ne $true)) {
        $GpuMode='Unconfigured'
    }
    $IdracHost=$IdracHost.Trim().TrimEnd('.').ToLowerInvariant()
    Add-Type -AssemblyName System.Security
    $bytes=[Security.Cryptography.ProtectedData]::Unprotect(
        [Convert]::FromBase64String($settings.IdracPassProtected),$null,
        [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $IdracPass=[Text.Encoding]::UTF8.GetString($bytes)
    [Array]::Clear($bytes,0,$bytes.Length)
    $bundledIpmi=Join-Path $PSScriptRoot 'Tools\IPMI\ipmitool.exe'
    $useBundled=if($null -ne $settings.UseBundledIpmi){[bool]$settings.UseBundledIpmi}else{Test-Path -LiteralPath $bundledIpmi}
    if($useBundled -or $IpmiExe -eq 'Bundled'){
        if(-not (Test-Path -LiteralPath $bundledIpmi)){throw 'Bundled IPMI runtime missing; repair the Thermal Ops installation'}
        $IpmiExe=$bundledIpmi
    }
    $IpmiExe=(Get-Command $IpmiExe -CommandType Application -ErrorAction Stop).Source
    # Confirm model before issuing R730-specific raw commands.
    # FRU inventory is slower than routine telemetry on this iDRAC.
    $routineTimeout=$CommandTimeoutSeconds
    try {
        $CommandTimeoutSeconds=25
        $model=Invoke-Ipmi @('fru','print')
    } catch { $model='' } finally { $CommandTimeoutSeconds=$routineTimeout }
    $TargetIdentity=Convert-TargetIdentity $model
    $mcInfo='';try{$mcInfo=Invoke-Ipmi @('mc','info')}catch{}
    if($RequestedLive -and (-not $model -or -not $mcInfo)){throw 'Server identity read unavailable; retry discovery before cooling'}
    $compatibility=Get-DellCompatibility $TargetIdentity $mcInfo
    foreach($property in $compatibility.PSObject.Properties){$TargetIdentity | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force}
    if(-not $compatibility.ManualControlAllowed){$Live=[switch]$false;$Smart=[switch]$false;$TargetIdentity.CoolingProfile='Monitoring only'}
    if($Live -and ($GpuMode -notin @('Local','ServerOnly') -or $settings.GpuSourceConfirmed -ne $true)){throw 'Configure and confirm the GPU source before cooling'}
    # Only live workers claim the control lock; read-only monitoring is permitted.
    $key=$IdracHost -replace '[^a-zA-Z0-9.-]','_'
    if ($Live) {
    $Mutex=New-Object Threading.Mutex($false,"Global\R730FanController_$key")
    try { $OwnMutex=$Mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $OwnMutex=$true }
    if (-not $OwnMutex) { throw 'Another controller instance is running for this iDRAC' }
    }
    $targetSerial=Get-TargetSystemSerial $model
    if($Live){
        if([string]::IsNullOrWhiteSpace($targetSerial) -or $targetSerial -match '^(Unknown|None|Default|To be filled)'){
            throw 'A usable server identity is required to prevent duplicate control through address aliases'
        }
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$physicalKey=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($targetSerial.Trim().ToUpperInvariant())))).Replace('-','')}finally{$hash.Dispose()}
        $PhysicalMutex=New-Object Threading.Mutex($false,('Global\R730FanPhysical_'+$physicalKey))
        try{$OwnPhysicalMutex=$PhysicalMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$OwnPhysicalMutex=$true}
        if(-not $OwnPhysicalMutex){throw 'This physical server already has a live worker under another profile/address'}
    }
    if($Live -and $GpuMode -eq 'Local'){
        $localSerial=[string](Get-CimInstance -ClassName Win32_BIOS -OperationTimeoutSec 4 -ErrorAction Stop).SerialNumber
        if([string]::IsNullOrWhiteSpace($targetSerial) -or [string]::IsNullOrWhiteSpace($localSerial) -or
            $targetSerial -match '^(Unknown|None|Default|To be filled)' -or $targetSerial.Trim() -ne $localSerial.Trim()){
            throw 'Local GPU telemetry does not match this server identity. Remote chassis-cooled GPUs need an on-server controller; server-only mode requires no chassis-cooled GPUs.'
        }
    }
    $DellRecoveryPath=Join-Path (Split-Path -Parent $SettingsPath) 'Dell-Auto-Recovery.pending'
    if($Live -and (Test-Path -LiteralPath $DellRecoveryPath)){
        # After a failed restoration or interrupted worker, return to auto first.
        $recovery=Get-Content -LiteralPath $DellRecoveryPath -Raw | ConvertFrom-Json
        if($recovery.Host -ne $IdracHost -or $recovery.Serial -ne $targetSerial){throw 'Pending Dell recovery target does not match hardware identity'}
        Set-AutoFanMode
        Remove-Item -LiteralPath $DellRecoveryPath -ErrorAction Stop
    }
    # One bounded read-only inventory query per worker session; never guess raw control bytes.
    try{$Discovery=@(Convert-SdrLocators (Invoke-Ipmi @('sdr','elist','all')))}catch{$Discovery=@()}
    $MonitorLocalGpu=$false
    if(-not $Live){
        $Smart=[switch]$false
        if($GpuMode -eq 'Local' -and $settings.GpuSourceConfirmed -eq $true){
            try{
                $localSerial=[string](Get-CimInstance -ClassName Win32_BIOS -OperationTimeoutSec 4 -ErrorAction Stop).SerialNumber
                $MonitorLocalGpu=-not [string]::IsNullOrWhiteSpace($targetSerial) -and $targetSerial -notmatch '^(Unknown|None|Default|To be filled)' -and $targetSerial.Trim() -eq $localSerial.Trim()
            }catch{}
        }
    }
    Clear-Host
    try { [Console]::CursorVisible=$false } catch {}
    for ($iteration=0; $iteration -lt $Iterations; $iteration++) {
        if ($StopPath -and (Test-Path -LiteralPath $StopPath)) { break }
        $sampleStart=$Clock.Elapsed.TotalSeconds
        if(-not $Live){
            $Ipmi=Convert-DellMonitorTelemetry (Invoke-Ipmi @('sensor'))
            $LastFan=-1;$Gpu=$null;$gpuNote='Server sensors only; local GPUs are not mapped to this target'
            if($MonitorLocalGpu){try{$Gpu=Get-GpuTelemetry;$gpuNote='Matching local GPUs monitored'}catch{$gpuNote='Local GPU telemetry unavailable'}}
            if($Clock.Elapsed.TotalSeconds-$sampleStart -gt $TelemetryBudgetSeconds){throw 'Telemetry collection exceeded freshness budget'}
            Write-AppStatus 'MONITORING' ($compatibility.Reason+' | '+$gpuNote) $Ipmi $Gpu
            if($iteration+1 -lt $Iterations){foreach($tick in 1..10){if($StopPath -and (Test-Path -LiteralPath $StopPath)){break};Start-Sleep -Milliseconds 200}}
            continue
        }
        $Ipmi=Get-IpmiTelemetry
        $Gpu=if($GpuMode -eq 'Local'){Get-GpuTelemetry}else{
            [pscustomobject]@{Temp=$null;Util=$null;Power=$null;Count=0;Cards=@();OptionalMissing=$false;Warning='Server sensors only: chassis-cooled GPUs excluded by profile confirmation'}
        }
        $seconds=$Clock.Elapsed.TotalSeconds
        if ($seconds-$sampleStart -gt $TelemetryBudgetSeconds) { throw 'Telemetry collection exceeded freshness budget' }
        Assert-SensorInventory $Ipmi $Gpu
        Test-FanResponse $Ipmi $seconds
        if(-not $ManualAttempted -and $Live){
            $preflight++
            if($preflight -lt 3){Write-AppStatus 'VALIDATING' ('Complete telemetry sample '+$preflight+'/3 before takeover') $Ipmi $Gpu;Start-Sleep -Seconds $PollSeconds;continue}
        }
        $target=Get-GpuSafeTarget $Ipmi $Gpu $seconds
        if ($Smart) { $target=Get-SmartTarget $Ipmi $Gpu $seconds $target }
        $target=Get-CustomCurveTarget $settings $Ipmi $Gpu $target
        if ($StopPath -and (Test-Path -LiteralPath $StopPath)) { break }
        if (-not $ManualAttempted) {
            # Fresh telemetry determines startup; never blindly command 15%.
            $target=[math]::Max($FailSafeFan,$target)
            if ($Live) { [IO.File]::WriteAllText($DellRecoveryPath,(@{Host=$IdracHost;Serial=$targetSerial}|ConvertTo-Json -Compress));$ManualAttempted=$true; Set-ManualFanMode }
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
        if ($Smart) { $action=$SmartReason }
        if($settings.FanCurveMode -eq 'Custom'){$action='Custom graph demand; original thermal safety floor enforced'}
        if($settings.FanCurveMode -eq 'Manual'){$action='Manual percentage request; original thermal safety floor enforced'}
        if ($Gpu.Warning) { $action=$Gpu.Warning }
        Write-AppStatus $mode $action $Ipmi $Gpu
        Write-Dashboard $Ipmi $Gpu $LastFan $mode $action $CooldownRemaining 'None'
        # Keep polling during startup; no blind settle sleep.
        if ($iteration+1 -lt $Iterations) {
            for ($tick=0; $tick -lt $PollSeconds*5; $tick++) {
                if ($StopPath -and (Test-Path -LiteralPath $StopPath)) { break }
                Start-Sleep -Milliseconds 200
            }
        }
    }
} catch {
    $failure=$_.Exception.Message
    $ExitReason=Get-ControllerExitReason $failure
    $RetryAllowed=$ExitReason -in @('TelemetryUnavailable','ConnectionOrCommandFailure')
    Write-AppStatus 'FAULT' $failure
    if ($ManualAttempted) {
        # Never lower an emergency/high command on telemetry failure.
        try { Set-FanPercent 100; $LastFan=100 } catch { Write-Warning 'Emergency 100% command failed.' }
    }
    Write-Warning "Controller stopped: $failure"
    throw
} finally {
    if(-not $failure){$ExitReason=if($StopPath -and (Test-Path -LiteralPath $StopPath)){'UserStop'}else{'Completed'}}
    if($StopPath -and (Test-Path -LiteralPath $StopPath)){$RetryAllowed=$false}
    if ($ManualAttempted) {
        Write-AppStatus 'Restoring' 'Returning control to Dell automatic cooling'
        $restored=$false
        foreach ($attempt in 1..3) {
            try { Set-AutoFanMode; $restored=$true; break } catch { Write-Warning "Automatic mode restore attempt $attempt failed." }
        }
        if ($restored) { if($DellRecoveryPath -and (Test-Path -LiteralPath $DellRecoveryPath)){Remove-Item -LiteralPath $DellRecoveryPath -ErrorAction SilentlyContinue};Write-AppStatus 'Stopped' 'Dell automatic control command accepted'; Write-Host 'Dell automatic fan control command accepted.' }
        else { Write-AppStatus 'RESTORE FAILED' 'Restore Dell cooling manually NOW'; Write-Warning 'AUTOMATIC RESTORE FAILED. Check iDRAC and restore cooling control manually NOW.' }
    }
    if (-not $ManualAttempted -and -not $failure) { Write-AppStatus 'Stopped' 'Read-only monitor stopped' }
    try { [Console]::CursorVisible=$true } catch {}
    if ($OwnMutex) { $Mutex.ReleaseMutex() }
    if ($null -ne $Mutex) { $Mutex.Dispose() }
    if ($OwnPhysicalMutex) { $PhysicalMutex.ReleaseMutex() }
    if ($null -ne $PhysicalMutex) { $PhysicalMutex.Dispose() }
}
