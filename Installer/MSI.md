# Ready-made Windows MSI

Download **Thermal-Ops-Setup-1.5.0.msi** from the GitHub release. It is a complete native Windows Installer package containing Thermal Ops, IPMI, local hardware runtime, Redfish scripts, notices and corresponding third-party sources. It does not download these dependencies during installation. Windows 10/11 x64 and .NET Framework 4.7.2 or newer are required. The optional PawnIO driver remains a separate user-initiated setup from inside the app.

Double-click the MSI and follow the wizard. Desktop and Windows sign-in startup shortcuts are selectable features, enabled by default. Installation is per user in `%LocalAppData%\Programs\Thermal Ops`. Profiles and modified settings are preserved during repair and uninstall. The installer is unsigned.

Use **tray Exit** and wait for cooling restoration before installing, repairing or uninstalling. The MSI checks for running app/worker processes and blocks the operation instead of terminating them. Windows Restart Manager shutdown is disabled. Monitoring processes also need to stop for maintenance.

Use one installer format. To switch from the EXE edition, exit safely and uninstall the EXE edition first. Its saved profiles/settings remain in the app folder. The MSI then installs in the same location and preserves them. Do not install the EXE edition over an MSI installation. For a portable copy, use **Import old settings** inside the installed app. The MSI does not have the EXE wizard's optional profile-import page.

Unattended per-user install (run as the intended Windows user):

```powershell
msiexec.exe /i Thermal-Ops-Setup-1.5.0.msi /qn /norestart
```

To install without desktop/startup shortcuts, add `ADDLOCAL=Core`. Use `ADDLOCAL=Core,Desktop` to keep the desktop shortcut only. Silent maintenance also requires all cooling workers to be stopped first. No automatic app launch occurs at the end of installation.

## Build

Prepare the regular 1.5.0 application payload using the repository's build instructions, then run:

```powershell
.\Installer\Prepare-MsiTools.ps1
.\Installer\Build-Msi.ps1 -WixPath .\Installer\Tools\WiX3
```

WiX 3.14.1 tools and corresponding source are downloaded from pinned official GitHub URLs and checked by SHA-256. MSI build output is in `Dist`. All applicable Windows Installer ICE checks run; ICE91 is excluded because this package deliberately supports per-user installation only and rejects ALLUSERS. File component GUIDs are stable across rebuilds. For future major releases, update the version and ProductCode while preserving UpgradeCode and component GUIDs.

`Build-Msi.ps1 -Smoke` builds an isolated packaging-test product with a different product code, upgrade code, app name and shortcuts. It deliberately omits the production cooling-process check so it can be tested without disturbing a running controller. Never publish the packaging-test MSI.

WiX tool source and licence are included under `Licenses`. The standalone Thermal Ops installer helper and application code are MIT licensed.

## Validation

The isolated Windows test verified all 76 installed payload file hashes, desktop and startup shortcut targets, startup arguments, factory defaults, repair retention, shortcut removal and preservation of user settings/profiles after uninstall. It never launched the app or changed fan control. The production cooling-process detector was also verified against an active controller.
