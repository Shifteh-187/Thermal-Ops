$ErrorActionPreference='Stop'
$test=Join-Path $PSScriptRoot ('MsiBuild\Handoff-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $test -Force|Out-Null
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
# Only this isolated test substitutes process discovery. Production includes MsiActions.cs.
[IO.File]::WriteAllText((Join-Path $test 'Stub.cs'),'public class MsiActions { public static bool CoolingActive(){return false;} }')
[IO.File]::WriteAllText((Join-Path $test 'FakeSetup.cs'),'using System; using System.IO; class FakeSetup { static void Main(){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"launched.txt"),"ok");} }')
[IO.File]::WriteAllText((Join-Path $test 'Parent.cs'),'class Parent {static void Main(){System.Threading.Thread.Sleep(4000);}}')
& $compiler /nologo /target:winexe ('/out:'+(Join-Path $test 'Helper.exe')) /reference:System.Windows.Forms.dll (Join-Path $PSScriptRoot 'UpdateLauncher.cs') (Join-Path $test 'Stub.cs')
if($LASTEXITCODE){throw 'Helper compilation failed'}
& $compiler /nologo /target:winexe ('/out:'+(Join-Path $test 'FakeSetup.exe')) (Join-Path $test 'FakeSetup.cs')
if($LASTEXITCODE){throw 'Fixture compilation failed'}
& $compiler /nologo /target:winexe ('/out:'+(Join-Path $test 'Parent.exe')) (Join-Path $test 'Parent.cs')
if($LASTEXITCODE){throw 'Parent compilation failed'}
$parent=Start-Process (Join-Path $test 'Parent.exe') -PassThru -WindowStyle Hidden
$installer=Join-Path $test 'FakeSetup.exe'
$helper=Start-Process (Join-Path $test 'Helper.exe') -ArgumentList ($parent.Id.ToString()+' "'+$installer+'" '+(Get-FileHash $installer).Hash) -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 500
if(Test-Path (Join-Path $test 'launched.txt')){throw 'Installer launched before parent exited'}
if(-not $helper.WaitForExit(15000)){throw 'Helper did not finish'}
if($helper.ExitCode -ne 0){throw 'Helper failed'}
for($i=0;$i -lt 20 -and -not(Test-Path (Join-Path $test 'launched.txt'));$i++){Start-Sleep -Milliseconds 100}
if(-not(Test-Path (Join-Path $test 'launched.txt'))){throw 'Test installer did not launch'}
'PASS: handoff waits for dashboard exit, verifies the checksum, then launches an isolated dummy installer.'
