$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\R730-App-Fleet\Controller.ps1') -LibraryOnly
$checks=0
function Check($condition,$message){if(-not $condition){throw $message};$script:checks++}
function Reject([scriptblock]$code){$failed=$false;try{& $code|Out-Null}catch{$failed=$true};Check $failed 'Invalid curve settings accepted'}
$points=@([pscustomobject]@{Temperature=20;Percent=20},[pscustomobject]@{Temperature=60;Percent=60},[pscustomobject]@{Temperature=80;Percent=100})
$curve=[pscustomobject]@{Source='CpuMax';Enabled=$true;Points=$points}
$config=[pscustomobject]@{FanCurveMode='Custom';FanCurves=@($curve)}
Assert-CustomFanSettings $config
foreach($temp in @(-10,0,20,30,40,60,70,80,100)){
    $expected=if($temp -le 20){20}elseif($temp -le 60){$temp}elseif($temp -lt 80){60+2*($temp-60)}else{100}
    Check ((Get-CurvePercent $points $temp) -eq $expected) 'Interpolation or endpoint clamp incorrect'
}
$ipmi=[pscustomobject]@{CpuMax=40;Exhaust=30;Inlet=22;SystemMax=45;Temps=@([pscustomobject]@{Name='Temp';Value=39},[pscustomobject]@{Name='Temp';Value=40})}
$gpu=[pscustomobject]@{Temp=55;Util=0;Power=0;OptionalMissing=$false}
Check ((Get-CustomCurveTarget $config $ipmi $gpu 55) -eq 55) 'Custom curve lowered original floor'
Check ((Get-CustomCurveTarget $config $ipmi $gpu 15) -eq 40) 'Custom curve demand ignored'
Check ((Get-CustomCurveTarget $config $ipmi $gpu 100) -eq 100) 'Emergency demand lowered'
$curve.Source='Temp:Temp:1';Check ((Get-CustomCurveTarget $config $ipmi $gpu 10) -eq 40) 'Duplicate-name sensor selection failed'
$curve.Source='GpuMax';$gpu.Temp=$null;Reject {Get-CustomCurveTarget $config $ipmi $gpu 10};$gpu.Temp=55
$curve.Source='Temp:Temp:2';Reject {Get-CustomCurveTarget $config $ipmi $gpu 10}
$curve.Source='CpuMax';$curve.Enabled=$false;Reject {Assert-CustomFanSettings $config};$curve.Enabled=$true
$config.FanCurves=@($curve,$curve);Reject {Assert-CustomFanSettings $config};$config.FanCurves=@($curve)
$curve.Points=@([pscustomobject]@{Temperature=40;Percent=20},[pscustomobject]@{Temperature=40;Percent=60});Reject {Assert-CustomFanSettings $config}
$curve.Points=@([pscustomobject]@{Temperature=20;Percent=60},[pscustomobject]@{Temperature=40;Percent=20});Reject {Assert-CustomFanSettings $config}
$curve.Points=@([pscustomobject]@{Temperature=20;Percent='NaN'},[pscustomobject]@{Temperature=40;Percent=60});Reject {Assert-CustomFanSettings $config}
$manual=[pscustomobject]@{FanCurveMode='Manual';ManualFanPercent=50};Assert-CustomFanSettings $manual
Check ((Get-CustomCurveTarget $manual $ipmi $gpu 80) -eq 80) 'Manual request defeated thermal floor'
Check ((Get-CustomCurveTarget $manual $ipmi $gpu 20) -eq 50) 'Manual request not applied'
$manual.ManualFanPercent=0;Reject {Assert-CustomFanSettings $manual};$manual.ManualFanPercent=101;Reject {Assert-CustomFanSettings $manual}
$config.FanCurveMode='Invalid';Reject {Assert-CustomFanSettings $config}
"PASS: $checks fan curve interpolation, bounds, safety floor, sensor binding and malformed configuration checks. No hardware access."
