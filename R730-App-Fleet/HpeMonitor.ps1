param([Parameter(Mandatory=$true)][string]$SettingsPath,[Parameter(Mandatory=$true)][string]$StatusPath,[Parameter(Mandatory=$true)][string]$StopPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hpe-Redfish.ps1')
Add-Type -AssemblyName System.Security
$config=Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
$origin=[Uri]('https://'+$config.IdracHost+'/')
$watch=[Diagnostics.Stopwatch]::StartNew()
$headers=@{};$identity=$null;$mutex=$null;$owned=$false
function Write-HpeStatus([string]$State,[string]$Message,$Telemetry=$null) {
    $data=@{Time=(Get-Date -Format o);State=$State;Message=$Message;Live=$false;Smart=$false;Fan=-1;Ipmi=$Telemetry;Gpu=$null;ManagementProvider='HPE';TargetIdentity=$identity;IdracHost=$config.IdracHost;ProfileName=$config.ProfileName;CooldownRemaining=0;UptimeSeconds=[int]$watch.Elapsed.TotalSeconds}
    [IO.File]::WriteAllText($StatusPath+'.tmp',($data | ConvertTo-Json -Depth 12 -Compress))
    Move-Item -LiteralPath ($StatusPath+'.tmp') -Destination $StatusPath -Force
}
function Get-HpeResource([string]$Path) {
    if (Test-Path -LiteralPath $StopPath) { throw 'Stop requested' }
    $url=[Uri]::new($origin,$Path)
    if ($url.Scheme -ne 'https' -or $url.Host -ne $origin.Host -or $url.Port -ne $origin.Port -or -not $url.AbsolutePath.StartsWith('/redfish/v1/')) { throw 'Untrusted Redfish resource link' }
    # Certificate validation stays enabled; redirects must never forward credentials.
    $response=Invoke-WebRequest -Uri $url.AbsoluteUri -Headers $headers -Method Get -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 0
    return ($response.Content | ConvertFrom-Json)
}
try {
    $sha=[Security.Cryptography.SHA256]::Create()
    try {$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($origin.Host.ToLowerInvariant()))).Replace('-','')} finally {$sha.Dispose()}
    $mutex=[Threading.Mutex]::new($false,('Global\ThermalOps-HPE-'+$key))
    try {$owned=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$owned=$true}
    if (-not $owned) {throw 'An HPE monitor already owns this target'}
    $password=[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($config.IdracPassProtected),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
    $headers.Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($config.IdracUser+':'+$password));$password=$null
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    Write-HpeStatus 'Starting' 'Discovering HPE iLO Redfish (monitoring only)'
    $root=Get-HpeResource '/redfish/v1/'
    $systems=Get-HpeResource $root.Systems.'@odata.id';$chassis=Get-HpeResource $root.Chassis.'@odata.id'
    if (@($systems.Members).Count -ne 1 -or @($chassis.Members).Count -ne 1) {throw 'This release requires one system and one chassis per iLO endpoint'}
    $systemPath=$systems.Members[0].'@odata.id';$chassisPath=$chassis.Members[0].'@odata.id'
    $system=Get-HpeResource $systemPath
    if ($system.Manufacturer -notmatch 'HPE|Hewlett|HP\b') {throw 'Endpoint did not identify as an HPE server'}
    $identity=@{Manufacturer=[string]$system.Manufacturer;Model=[string]$system.Model;Source='iLO Redfish';CoolingProfile='HPE automatic cooling / monitor only'}
    while (-not (Test-Path -LiteralPath $StopPath)) {
        try {
            $system=Get-HpeResource $systemPath;$enclosure=Get-HpeResource $chassisPath
            $thermal=$null;$power=$null
            if ($enclosure.Thermal.'@odata.id') {$thermal=Get-HpeResource $enclosure.Thermal.'@odata.id'}
            if ($enclosure.Power.'@odata.id') {$power=Get-HpeResource $enclosure.Power.'@odata.id'}
            $telemetry=Convert-HpeTelemetry $system $thermal $power
            Write-HpeStatus 'MONITORING' 'HPE monitoring only; iLO retains automatic cooling' $telemetry
        } catch {if (Test-Path -LiteralPath $StopPath) {break};Write-HpeStatus 'FAULT' 'HPE telemetry unavailable; check certificate, credentials and Redfish support'}
        foreach ($tick in 1..20) {if (Test-Path -LiteralPath $StopPath) {break};Start-Sleep -Milliseconds 500}
    }
    Write-HpeStatus 'Stopped' 'Read-only monitor stopped'
} catch {if (Test-Path -LiteralPath $StopPath) {Write-HpeStatus 'Stopped' 'Read-only monitor stopped'} else {Write-HpeStatus 'FAULT' 'HPE connection failed; check trusted HTTPS certificate, credentials and supported Redfish resources';exit 1}}
finally {$headers.Clear();if ($owned) {$mutex.ReleaseMutex()};if ($mutex) {$mutex.Dispose()}}
