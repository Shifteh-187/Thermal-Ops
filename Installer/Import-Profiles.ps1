param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath $Source -PathType Container)) {throw 'Old profile folder was not found'}
$app=Join-Path $PSScriptRoot 'ThermalOps.exe'
& $app --import-profiles $Source $Destination
if ($LASTEXITCODE) {throw 'Settings import failed. See import-result.txt in the app folder.'}
