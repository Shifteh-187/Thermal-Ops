$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\R730-App-Fleet\Controller.ps1') -LibraryOnly
$script:Live=$true;$checks=0
function Check($ok,$message){if(-not $ok){throw $message};$script:checks++}
function Reading([double]$Rpm){[pscustomobject]@{Fans=@([pscustomobject]@{Name='Fan1';Value=$Rpm})}}
function Arm([double]$Rpm=11000){$script:ResponseCheck=$null;$script:LastFanChangeTime=0;$script:LastFan=60;Register-FanResponseCommand (Reading $Rpm) 60 40 100}
Register-FanResponseCommand (Reading 11000) 100 -1 10
Check ($null -eq $ResponseCheck) 'Startup at high RPM armed an invalid response test'
$script:LastFanChangeTime=85;Register-FanResponseCommand (Reading 11000) 80 60 100
Check ($null -eq $ResponseCheck) 'Unsettled prior command armed a test'
Arm;Check ($null -ne $ResponseCheck) 'Stable substantial increase not monitored'
Test-FanResponse (Reading 11000) 130
Check ($null -eq $ResponseCheck -and $FanResponseNotice -like 'RPM rise unconfirmed*') 'Already-fast flat RPM caused a false hardware fault'
Arm 4000;Test-FanResponse (Reading 6000) 130
Check ($FanResponseNotice -like 'RPM increase observed*') 'Real RPM response not observed'
Arm;Register-FanResponseCommand (Reading 11000) 57 60 110
Check ($null -eq $ResponseCheck) 'Decreasing demand kept obsolete rise test'
Arm;Register-FanResponseCommand (Reading 11000) 65 60 110
Check ($null -eq $ResponseCheck) 'Retargeting kept obsolete rise test'
Arm;$script:LastFan=40;Test-FanResponse (Reading 11000) 130
Check ($null -eq $ResponseCheck) 'Mismatched requested duty test not cancelled'
Arm 6000;Test-FanResponse (Reading 4000) 130
Check ($null -ne $ResponseCheck) 'One transient drop was not debounced'
Test-FanResponse (Reading 6000) 132
Check ($FanResponseNotice -like 'RPM rise unconfirmed*') 'Recovered transient drop remained latched'
Arm 6000;Test-FanResponse (Reading 4000) 130;Test-FanResponse (Reading 4000) 132
$failed=$false;try{Test-FanResponse (Reading 4000) 134}catch{$failed=$_.Exception.Message -like 'Fan RPM fell substantially*'}
Check $failed 'Persistent large RPM drop accepted'
Arm;$failed=$false;try{Test-FanResponse (Reading 0) 130}catch{$failed=$_.Exception.Message -match 'missing or stalled'}
Check $failed 'Stalled fan accepted'
Arm;$failed=$false;try{Test-FanResponse ([pscustomobject]@{Fans=@()}) 130}catch{$failed=$true}
Check $failed 'Missing fan accepted'
"PASS: $checks startup/high-RPM, settled baseline, cancellation, positive response, drop debounce and genuine fault checks. No hardware writes."
