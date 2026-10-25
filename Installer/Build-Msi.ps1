param([Parameter(Mandatory=$true)][string]$WixPath,[switch]$Smoke)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$payload=Join-Path $PSScriptRoot 'Payload'
$build=Join-Path $PSScriptRoot 'MsiBuild'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$WixPath=(Resolve-Path $WixPath).Path
$factory=Get-Content (Join-Path $payload 'settings.json') -Raw|ConvertFrom-Json
if($factory.IdracPassProtected -or $factory.IdracHost -ne '127.0.0.1' -or $factory.GpuSourceConfirmed){throw 'MSI requires unconfigured factory settings, never deployment settings'}
# Include build-tool source and licence for reference.
foreach($notice in @('WiX-MS-RL.txt','WiX-3.14.1-source.zip','MSI-THIRD-PARTY.txt')){if(-not(Test-Path (Join-Path $payload ('Licenses\'+$notice)))){throw 'Run Prepare-MsiTools.ps1 to stage the WiX licence and source'}}
$version='1.5.1'
if([Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $payload 'ThermalOps.exe')).FileVersion -ne ($version+'.0')){throw 'Build the matching application payload first'}
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe ('/out:'+(Join-Path $build 'MsiActions.exe')) /reference:System.Management.dll (Join-Path $PSScriptRoot 'MsiActions.cs')
if($LASTEXITCODE){throw 'MSI action compilation failed'}
function EscapeXml([string]$value){[Security.SecurityElement]::Escape($value)}
function StableId([string]$value){$sha=[Security.Cryptography.SHA256]::Create();try{'I'+([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value.ToLowerInvariant())))).Replace('-','').Substring(0,30)}finally{$sha.Dispose()}}
function StableGuid([string]$value){$sha=[Security.Cryptography.SHA256]::Create();try{$bytes=$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value.ToLowerInvariant()));([guid]::new([byte[]]$bytes[0..15])).ToString()}finally{$sha.Dispose()}}
$name=if($Smoke){'Thermal Ops MSI Packaging Test'}else{'Thermal Ops'}
$upgrade=if($Smoke){'AE91DC35-67EF-4275-8774-24557B431162'}else{'C916336D-6773-494F-A09F-B61FB1F628A0'}
$product=if($Smoke){'513AB234-EBC1-4A22-A544-60E55208DDA6'}else{'F8748E72-4069-4501-B5C7-35A61A997567'}
$xml=New-Object Text.StringBuilder
[void]$xml.AppendLine(('<?xml version="1.0" encoding="utf-8"?><Wix xmlns="http://schemas.microsoft.com/wix/2006/wi"><Product Id="'+$product+'" Name="'+$name+'" Language="1033" Version="'+$version+'" Manufacturer="Chris Ramsay" UpgradeCode="'+$upgrade+'">'))
[void]$xml.AppendLine('<Package InstallerVersion="500" Compressed="yes" InstallScope="perUser" Platform="x64" Description="Thermal Ops - made by Chris Ramsay 2026"/><MediaTemplate EmbedCab="yes" CompressionLevel="mszip"/><MajorUpgrade DowngradeErrorMessage="A newer Thermal Ops MSI is installed." Schedule="afterInstallInitialize"/>')
[void]$xml.AppendLine('<Property Id="MSIRESTARTMANAGERCONTROL" Value="Disable"/><Property Id="REBOOT" Value="ReallySuppress"/><Property Id="ARPNOMODIFY" Value="1"/><Property Id="ARPHELPLINK" Value="https://github.com/Shifteh-187/Thermal-Ops"/><Property Id="ARPPRODUCTICON" Value="AppIcon"/>')
[void]$xml.AppendLine('<Property Id="NETFRAMEWORKRELEASE"><RegistrySearch Id="NetFramework" Root="HKLM" Key="SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" Name="Release" Type="raw" Win64="yes"/></Property><Property Id="OSBUILD"><RegistrySearch Id="WindowsBuildNumber" Root="HKLM" Key="SOFTWARE\Microsoft\Windows NT\CurrentVersion" Name="CurrentBuildNumber" Type="raw" Win64="yes"/></Property><Condition Message="Windows 10 or newer (64-bit) is required.">Installed OR (VersionNT64 AND OSBUILD &gt;= 10240)</Condition><Condition Message=".NET Framework 4.7.2 or newer is required.">Installed OR NETFRAMEWORKRELEASE &gt;= &quot;#461808&quot;</Condition>')
if(-not $Smoke){
 [void]$xml.AppendLine('<Property Id="LEGACYINSTALL"><RegistrySearch Id="LegacyInno" Root="HKCU" Key="Software\Microsoft\Windows\CurrentVersion\Uninstall\{0E037054-3EE5-48D6-B482-7798015CBB11}_is1" Name="DisplayName" Type="raw"/></Property><Condition Message="The EXE installer edition is installed. Exit Thermal Ops safely, uninstall that edition, then run this MSI. Saved profiles and settings are retained. Do not install both formats together.">Installed OR NOT LEGACYINSTALL</Condition>')
}
[void]$xml.AppendLine(('<Icon Id="AppIcon" SourceFile="'+(EscapeXml (Join-Path $payload 'ThermalOps.ico'))+'"/>'))
[void]$xml.AppendLine('<Directory Id="TARGETDIR" Name="SourceDir"><Directory Id="LocalAppDataFolder"><Directory Id="Programs" Name="Programs"><Directory Id="INSTALLFOLDER" Name="'+$name+'">')
$files=@(Get-ChildItem -LiteralPath $payload -File -Recurse | Where-Object {
 $rel=$_.FullName.Substring($payload.Length+1)
 $rel -notmatch '(^|\\)(Profiles|Runs|MsiBuild)(\\|$)' -and $rel -notmatch '(^|\\)[^\\]*-test\.txt$|\.jsonl$|(^|\\)(preview|.*-preview)\.png$|\.bak$'
})
$components=New-Object Collections.Generic.List[string]
# Generate nested directories and one component per file, using stable path-based IDs/GUIDs.
function EmitFolder([string]$relative,[string]$directoryId){
 $folder=if($relative){Join-Path $payload $relative}else{$payload}
 foreach($file in @($files|Where-Object {$_.DirectoryName -eq $folder})){
  $rel=$file.FullName.Substring($payload.Length+1);$id=StableId $rel;$components.Add($id)
  $targetName=if($rel -eq 'settings.json'){'settings.default.json'}else{$file.Name}
  [void]$xml.AppendLine(('<Component Id="'+$id+'" Guid="'+(StableGuid ($name+'/'+$rel))+'" Win64="yes"><File Id="F'+$id+'" Name="'+(EscapeXml $targetName)+'" Source="'+(EscapeXml $file.FullName)+'"/><RegistryValue Root="HKCU" Key="Software\Chris Ramsay\'+$name+'\Components" Name="'+$id+'" Type="integer" Value="1" KeyPath="yes"/><RemoveFolder Id="R'+$id+'" Directory="'+$directoryId+'" On="uninstall"/></Component>'))
 }
 foreach($child in @(Get-ChildItem -LiteralPath $folder -Directory)){
  $rel=$child.FullName.Substring($payload.Length+1)
  if(-not @($files|Where-Object {$_.FullName.StartsWith($child.FullName+'\',[StringComparison]::OrdinalIgnoreCase)}).Count){continue}
  $id=StableId ('dir/'+$rel)
  [void]$xml.AppendLine(('<Directory Id="'+$id+'" Name="'+(EscapeXml $child.Name)+'">'));EmitFolder $rel $id;[void]$xml.AppendLine('</Directory>')
 }
}
EmitFolder '' 'INSTALLFOLDER'
[void]$xml.AppendLine('</Directory></Directory></Directory><Directory Id="ProgramMenuFolder"><Directory Id="AppMenu" Name="'+$name+'"/></Directory><Directory Id="DesktopFolder"/><Directory Id="StartupFolder"/></Directory>')
foreach($shortcut in @(@{Id='MenuShortcut';Directory='AppMenu';Args=''},@{Id='DesktopShortcut';Directory='DesktopFolder';Args=''},@{Id='StartupShortcut';Directory='StartupFolder';Args='--startup'})){
 [void]$xml.AppendLine(('<DirectoryRef Id="'+$shortcut.Directory+'"><Component Id="'+$shortcut.Id+'" Guid="*" Win64="yes"><Shortcut Id="L'+$shortcut.Id+'" Name="'+$name+'" Target="[INSTALLFOLDER]ThermalOps.exe" Arguments="'+$shortcut.Args+'" WorkingDirectory="INSTALLFOLDER" Icon="AppIcon"/><RegistryValue Root="HKCU" Key="Software\Chris Ramsay\'+$name+'" Name="'+$shortcut.Id+'" Type="integer" Value="1" KeyPath="yes"/>'+$(if($shortcut.Id -eq 'MenuShortcut'){'<RemoveFolder Id="RemoveMenu" On="uninstall"/>'}else{''})+'</Component></DirectoryRef>'))
}
[void]$xml.AppendLine('<Feature Id="Core" Title="Thermal Ops application and bundled tools" Level="1" Absent="disallow" Display="expand"><ComponentRef Id="MenuShortcut"/>')
foreach($id in $components){[void]$xml.AppendLine('<ComponentRef Id="'+$id+'"/>')}
[void]$xml.AppendLine('</Feature><Feature Id="Desktop" Title="Desktop shortcut" Level="1"/><Feature Id="Startup" Title="Start Thermal Ops when I sign in" Level="1"/>')
# Attach optional shortcut components to their selectable features.
$text=$xml.ToString().Replace('<Feature Id="Desktop" Title="Desktop shortcut" Level="1"/>','<Feature Id="Desktop" Title="Desktop shortcut" Level="1"><ComponentRef Id="DesktopShortcut"/></Feature>').Replace('<Feature Id="Startup" Title="Start Thermal Ops when I sign in" Level="1"/>','<Feature Id="Startup" Title="Start Thermal Ops when I sign in" Level="1"><ComponentRef Id="StartupShortcut"/></Feature>')
$xml=New-Object Text.StringBuilder $text
[void]$xml.AppendLine('<Binary Id="MsiActions" SourceFile="'+(EscapeXml (Join-Path $build 'MsiActions.exe'))+'"/><CustomAction Id="CheckCooling" BinaryKey="MsiActions" ExeCommand="check" Execute="immediate" Return="check"/><CustomAction Id="InitializeSettings" BinaryKey="MsiActions" ExeCommand="initialize &quot;[INSTALLFOLDER].&quot;" Execute="deferred" Impersonate="yes" Return="check"/>')
[void]$xml.AppendLine('<InstallExecuteSequence>')
if(-not $Smoke){[void]$xml.AppendLine('<Custom Action="CheckCooling" Before="InstallValidate">NOT UPGRADINGPRODUCTCODE</Custom>')}
[void]$xml.AppendLine('<Custom Action="InitializeSettings" After="InstallFiles">NOT REMOVE~=&quot;ALL&quot;</Custom></InstallExecuteSequence><UIRef Id="WixUI_FeatureTree"/><UIRef Id="WixUI_ErrorProgressText"/></Product></Wix>')
# Remove empty application folders only; user-created profile/history files remain.
[xml]$tree=$xml.ToString()
$cleanup='<DirectoryRef Id="INSTALLFOLDER"><Component Id="FolderCleanup" Guid="*" Win64="yes"><RegistryValue Root="HKCU" Key="Software\Chris Ramsay\'+$name+'" Name="FolderCleanup" Type="integer" Value="1" KeyPath="yes"/>'
foreach($dir in $tree.SelectNodes('//*[local-name()="Directory"]')){
 if($dir.Id -notin @('TARGETDIR','LocalAppDataFolder','ProgramMenuFolder','DesktopFolder','StartupFolder')){$cleanup+='<RemoveFolder Id="Clean'+$dir.Id+'" Directory="'+$dir.Id+'" On="uninstall"/>'}
}
$cleanup+='<RegistryValue Root="HKCU" Key="Software\Chris Ramsay\'+$name+'" Name="InstallPath" Type="string" Value="[INSTALLFOLDER]"/></Component></DirectoryRef><Property Id="INSTALLFOLDER"><RegistrySearch Id="RememberInstallFolder" Root="HKCU" Key="Software\Chris Ramsay\'+$name+'" Name="InstallPath" Type="raw" Win64="yes"/></Property><Condition Message="This MSI supports per-user installation only.">NOT ALLUSERS</Condition>'
$xml.Replace('</Product>',($cleanup+'</Product>'))|Out-Null
$xml.Replace('<ComponentRef Id="MenuShortcut"/>','<ComponentRef Id="MenuShortcut"/><ComponentRef Id="FolderCleanup"/>')|Out-Null
$xml.Replace(' Arguments=""','')|Out-Null
$source=Join-Path $build 'ThermalOps.wxs';[IO.File]::WriteAllText($source,$xml.ToString())
$licence=([IO.File]::ReadAllText((Join-Path $root 'LICENSE')) -replace '\\','\\' -replace '\{','\{' -replace '\}','\}' -replace '\r?\n','\par ')
$rtf=Join-Path $build 'License.rtf';[IO.File]::WriteAllText($rtf,('{\rtf1\ansi '+$licence+'\par Third-party notices and corresponding sources are included in the application.}'))
$out=Join-Path $root ('Dist\Thermal-Ops-'+$(if($Smoke){'MSI-Test-'}else{'Setup-'})+$version+'.msi')
& (Join-Path $WixPath 'candle.exe') -nologo -arch x64 -out (Join-Path $build 'ThermalOps.wixobj') $source
if($LASTEXITCODE){throw 'MSI authoring compilation failed'}
& (Join-Path $WixPath 'light.exe') -nologo -sice:ICE91 -ext WixUIExtension ('-dWixUILicenseRtf='+$rtf) -out $out (Join-Path $build 'ThermalOps.wixobj')
if($LASTEXITCODE){throw 'MSI linking or validation failed'}
$out
