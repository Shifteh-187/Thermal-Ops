# Thermal Ops

Made by **Chris Ramsay, 2026**. Windows cooling control and monitoring with a dark dashboard, live temperature trends, individual server power graphs, fleet health and total power usage.

## Downloads

Use the Windows installer from **Releases** for the graphical app. The console ZIP keeps the original ASCII PowerShell dashboard available. The installer is unsigned; Windows may display a publisher warning.

## Hardware support

- **Dell R730:** IPMI fan control with the existing temperature curves, emergency thresholds, telemetry checks and restoration of automatic control on orderly exit.
- **HPE / other Redfish servers:** monitoring and capability-dependent controls. HPE thermal profiles and minimum fan settings require the firmware to expose them. These adapters have offline fixture tests; they have not been validated on physical HPE hardware.
- **Local PCs:** LibreHardwareMonitor sensor discovery and supported fan outputs. Select and verify the physical fan channels and temperature sources before enabling control. Not every GPU, motherboard, USB controller or laptop exposes writable controls.

See [hardware support](R730-App-Fleet/HARDWARE-SUPPORT.md), [HPE support](R730-App-Fleet/HPE-SUPPORT.md) and [GPU compatibility](R730-App-Fleet/GPU-COMPATIBILITY.md).

The GUI stores separate server credentials protected for the current Windows user. Closing the window hides it in the tray. Use **Exit** to stop controllers and request restoration of automatic cooling. Configure startup behaviour only after verifying your sensors and cooling response.

## Console version

Requires Windows PowerShell 5.1 and a Windows ipmitool executable. Set connection details in the current PowerShell session:

```powershell
$env:THERMAL_OPS_IDRAC_HOST = '192.0.2.10' # replace with your management address
$env:THERMAL_OPS_IDRAC_USER = 'root'
$env:THERMAL_OPS_IPMITOOL = 'C:\Tools\IPMI\ipmitool.exe'
.\R730-FanController-Smart.ps1
```

The password is requested securely when it is not supplied through `THERMAL_OPS_IDRAC_PASSWORD`. Default mode monitors without issuing fan control commands. After checking telemetry, use `-Live` to enable control. `R730-FanController.ps1` provides the original curve implementation; the Smart variant adds smoothing. Both preserve the ASCII dashboard and R730 thresholds.

Run only one controller against a physical server. These console scripts are R730-specific; never apply their raw commands to an unverified model. Abrupt termination, power loss or an operating system crash can prevent software restoration: keep independent hardware temperature protection enabled and check the result of exit restoration.

Offline checks (no hardware writes):

```powershell
.\Test-R730FanController.ps1
.\Test-R730SmartControl.ps1
```

## Build the Windows app

Requires Windows, .NET Framework 4.7.2 or newer, Windows PowerShell 5.1 and Inno Setup 6. Download the matching **build-dependencies** ZIP from Releases and extract it in the repository root; it supplies `Installer/Payload` with runtime dependencies and their licences. Then run:

```powershell
.\Installer\Build.ps1 -InnoCompiler 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
```

Output: `Dist/Thermal-Ops-Setup-1.2.2.exe`. The dependency archive includes upstream binaries, licence notices and required corresponding source archives. LibreHardwareMonitor 0.9.6 comes from its official GitHub release; PawnIO 2.1.0 is its bundled driver installer. The Windows ipmitool 1.8.19 build is distributed by Danny Nieuwenhuis, with provenance and hashes in `Installer/Payload/Tools/IPMI`. The optional PawnIO driver requires a separate installation with administrator approval.

## Licence

Thermal Ops code is [MIT licensed](LICENSE). Third-party software keeps its own licence; bundled notices and corresponding sources are distributed with the installer and dependency archive. Do not upload saved profiles, passwords, logs or telemetry when reporting an issue.
