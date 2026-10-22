param([string]$WixPath=(Join-Path $PSScriptRoot 'Tools\WiX3'))
$ErrorActionPreference='Stop'
function Get-PinnedFile([string]$Url,[string]$Path,[string]$Sha256){
    if(-not(Test-Path -LiteralPath $Path)){Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing}
    if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Sha256){throw ('Download checksum mismatch: '+[IO.Path]::GetFileName($Path))}
}
New-Item -ItemType Directory -Path $WixPath -Force|Out-Null
$archive=Join-Path $WixPath 'wix.zip'
Get-PinnedFile 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip' $archive '6AC824E1642D6F7277D0ED7EA09411A508F6116BA6FAE0AA5F2C7DAA2FF43D31'
Expand-Archive -LiteralPath $archive -DestinationPath $WixPath -Force
$licenses=Join-Path $PSScriptRoot 'Payload\Licenses';New-Item -ItemType Directory -Path $licenses -Force|Out-Null
Copy-Item (Join-Path $WixPath 'LICENSE.TXT') (Join-Path $licenses 'WiX-MS-RL.txt') -Force
Get-PinnedFile 'https://github.com/wixtoolset/wix3/archive/refs/tags/wix3141rtm.zip' (Join-Path $licenses 'WiX-3.14.1-source.zip') 'A56184E798885641821666BD389FE6276F99363F65BAE8F88630B17DE297FE9F'
@'
Built using WiX 3.14.1. Its licence and unmodified source are included for reference.
Copyright (c) .NET Foundation and contributors. Microsoft Reciprocal License (MS-RL).
Corresponding source: WiX-3.14.1-source.zip; licence: WiX-MS-RL.txt.
Thermal Ops action source: https://github.com/Shifteh-187/Thermal-Ops/blob/main/Installer/MsiActions.cs
Upstream: https://github.com/wixtoolset/wix3/tree/wix3141rtm
'@ | Set-Content (Join-Path $licenses 'MSI-THIRD-PARTY.txt')
$WixPath
