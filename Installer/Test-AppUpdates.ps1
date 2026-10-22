$ErrorActionPreference='Stop'
$test=Join-Path $PSScriptRoot ('MsiBuild\UpdateTests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $test -Force|Out-Null
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:exe ('/out:'+(Join-Path $test 'UpdateTests.exe')) /reference:System.Web.Extensions.dll /reference:System.Windows.Forms.dll (Join-Path $PSScriptRoot 'Test-AppUpdates.cs') (Join-Path (Split-Path $PSScriptRoot) 'R730-App-Fleet\AppUpdates.cs')
if($LASTEXITCODE){throw 'Test compilation failed'}
& (Join-Path $test 'UpdateTests.exe') $test
if($LASTEXITCODE){throw 'Updater tests failed'}
