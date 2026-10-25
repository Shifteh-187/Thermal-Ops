#define AppName "Thermal Ops"
#define AppVersion "1.5.1"
[Setup]
#ifdef ThermalOpsSmoke
AppId={{EAE89B89-1B1E-48DE-8553-4271EF508553}
AppName=Thermal Ops Packaging Test
DefaultGroupName=Thermal Ops Packaging Test
DefaultDirName={localappdata}\Programs\Thermal Ops Packaging Test
AppMutex=ThermalOps.PackagingTest
#else
AppId={{0E037054-3EE5-48D6-B482-7798015CBB11}
AppName={#AppName}
DefaultDirName={localappdata}\Programs\Thermal Ops
DefaultGroupName=Thermal Ops
AppMutex=ThermalOps.AppRunning
#endif
AppVersion={#AppVersion}
AppPublisher=Chris Ramsay
AppCopyright=Made by Chris Ramsay 2026
VersionInfoCompany=Chris Ramsay
VersionInfoDescription=Thermal Ops Setup
VersionInfoCopyright=Made by Chris Ramsay 2026
PrivilegesRequired=lowest
MinVersion=10.0
DisableProgramGroupPage=yes
DisableWelcomePage=no
OutputDir=..\Dist
OutputBaseFilename=Thermal-Ops-Setup-1.5.1
SetupIconFile=..\R730-App-Fleet\Assets\ThermalOps.ico
UninstallDisplayIcon={app}\ThermalOps.exe
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
CloseApplications=no
RestartApplications=no
Uninstallable=yes
InfoBeforeFile=INSTALL-NOTES.txt

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"
Name: startup; Description: "Start Thermal Ops when I sign in to Windows"; GroupDescription: "Startup:"
Name: importprofiles; Description: "Import saved profiles from an existing portable copy (same Windows user)"; GroupDescription: "Existing setup:"; Flags: unchecked

[Files]
Source: "Payload\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "settings.json,*-test.txt,*-preview.png,preview.png,Profiles\*,Runs\*,*.jsonl"
Source: "Payload\settings.json"; DestDir: "{app}"; Flags: onlyifdoesntexist

[Icons]
Name: "{group}\Thermal Ops"; Filename: "{app}\ThermalOps.exe"; AppUserModelID: "ChrisRamsay.ThermalOps"
Name: "{autodesktop}\Thermal Ops"; Filename: "{app}\ThermalOps.exe"; Tasks: desktopicon; AppUserModelID: "ChrisRamsay.ThermalOps"
Name: "{group}\Uninstall Thermal Ops"; Filename: "{uninstallexe}"
Name: "{userstartup}\Thermal Ops"; Filename: "{app}\ThermalOps.exe"; Parameters: "--startup"; Tasks: startup; AppUserModelID: "ChrisRamsay.ThermalOps"

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Import-Profiles.ps1"" -Source ""{code:ProfileSource}"" -Destination ""{app}\Profiles"""; Flags: runhidden waituntilterminated; Tasks: importprofiles
Filename: "{app}\ThermalOps.exe"; Description: "Launch Thermal Ops (configured cooling / monitoring)"; Flags: nowait postinstall skipifsilent unchecked

[Code]
var ImportPage: TInputDirWizardPage;
function InitializeSetup: Boolean;
var Release: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full', 'Release', Release) and (Release >= 461808);
  if not Result then
    MsgBox('Thermal Ops requires .NET Framework 4.7.2 or newer. Install .NET Framework 4.8, then run Setup again.', mbError, MB_OK);
end;
function ProfileSource(Param: String): String;
begin
  Result := AddBackslash(ImportPage.Values[0]) + 'Profiles';
end;
procedure InitializeWizard;
begin
  WizardForm.WelcomeLabel2.Caption := 'Made by Chris Ramsay 2026' + #13#10#13#10 + 'Multi-server cooling, live telemetry and power trends.';
  ImportPage := CreateInputDirPage(wpSelectTasks, 'Import existing server profiles', 'Select your existing Thermal Ops app folder', 'Profiles are copied locally. Their passwords stay encrypted for this Windows user. Existing installed profiles are kept. Running controllers are left running.', False, '');
  ImportPage.Add('Existing app folder:');
  ImportPage.Values[0] := ExpandConstant('{src}\..\R730-App-Fleet');
end;
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = ImportPage.ID) and (not WizardIsTaskSelected('importprofiles'));
end;
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = ImportPage.ID) and (not DirExists(ProfileSource(''))) then begin
    MsgBox('That folder does not contain a Profiles folder. Select the existing app folder or go back and turn off profile import.', mbError, MB_OK);
    Result := False;
  end;
end;
