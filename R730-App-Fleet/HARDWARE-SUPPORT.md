# Thermal Ops hardware support — 1.2.2

Made by Chris Ramsay 2026.

Thermal Ops now has separate paths for server BMCs and local gaming-PC/controller hardware. Detection is not a claim of universal control support. The app only writes through an implemented adapter after the target and required properties are checked.

| Technology / hardware | Implemented in this build | Verification |
|---|---|---|
| Dell PowerEdge R730 / iDRAC OEM IPMI | Existing temperature curves, smart option, fan/RPM checks, emergency handling and Dell automatic restoration | Existing R730 engine retained; no new live fan writes during this work |
| HPE iLO Redfish | Monitoring, native cooling profiles, optional exposed minimum fan percentage, original-setting recovery and read-back | Simulated transport and telemetry fixtures; physical HPE testing outstanding |
| Supermicro Redfish | Monitoring and advertised native FanMode values | Planning/validation fixtures; physical testing outstanding |
| Standard Redfish ThermalSubsystem | Monitoring and full-speed override when the resource exposes `FansFullSpeedOverrideEnable` | Capability planning tests; firmware dependent |
| Lenovo XCC, Cisco CIMC/UCS, Gigabyte, ASRock Rack, Fujitsu and OpenBMC | Shared Redfish monitoring where compatible Thermal/Power or ThermalSubsystem resources exist; standard full-speed override only when exposed | Generic API compatibility, not model certification; vendor-specific policies/CLI/D-Bus writes are not implemented |
| Gaming-PC motherboard PWM/DC headers | Local setup discovers LibreHardwareMonitor controls and temperature sensors; confirmed fan channels run a temperature curve | Compiled against upstream 0.9.6; curve/validation tests; board/driver dependent |
| USB fan hubs / AIO controllers | Same local path for writable channels exposed by LibreHardwareMonitor (its upstream groups include NZXT, Aqua Computer, AeroCool, Arctic, MSI, Razer, Heatmaster and T-Balancer) | A vendor group does not guarantee every model or channel is writable; physical testing required |
| NVIDIA / AMD GPU fans | Local path only where LibreHardwareMonitor exposes an actual writable fan control | Hardware/driver dependent; passive or physically removed fans must not be mapped |
| Corsair Commander, Lian Li and other liquidctl devices | Technology reviewed; no liquidctl control adapter bundled in this build | Use manufacturer software for models not exposed by the local backend |
| Laptop embedded controllers / ACPI / Dell SMM | Not implemented | Model-specific protocols are required |
| Linux hwmon/sysfs and OpenBMC D-Bus/PID configuration | Not implemented by this Windows app | Requires a host-side agent and platform-specific permissions |
| RGB-only hubs and passive splitters | No independent fan control unless a supported upstream fan header controls them | RGB discovery does not imply fan control |

## Local PC / standalone controller setup

Use **Local PC / controllers** in the toolbar or tray menu. Install the optional signed PawnIO driver using the setup-screen button if required by the hardware, then scan. Administrator access can be required for low-level motherboard access. The driver installer runs interactively; Thermal Ops does not silently install a kernel driver.

Select the physical fan channels (Ctrl-click for multiple) and a relevant temperature sensor, or the highest CPU/GPU temperature, set its full-speed temperature limit and confirm that it is a fan rather than a pump. No output is selected automatically. The current local adapter supports multiple selected fan channels in one profile per computer. It does not take ownership of every connected fan or automatically replace other cooling software. Stop conflicting vendor/third-party control of the selected channel before starting.

The local curve uses a 50% minimum, reaches 100% at the configured limit, ramps upward faster than downward and checks the selected sensor continuously. Missing/invalid temperature readings stop control and request driver defaults. Stop/Exit calls the driver's default-control method and blocks exit if it reports failure. Driver acceptance is not independent physical RPM or firmware-mode verification. A forced process termination or power loss cannot execute a software cleanup handler; vendor firmware behavior remains relevant.

For GPUs with removed or passive fans, monitor GPU temperature through the server controller and verify chassis airflow. Do not map a nonexistent GPU fan to the local control backend.

## Server-native controls

Add a management endpoint using **Add server**. Choose HPE, Supermicro or Other BMC. **Monitor BMC** reads telemetry. Choose the native profile on **Connection**, then **Apply native cooling**. HPE minimum speed is used only when explicitly enabled and exposed by that iLO. Supermicro mode names must appear in the BMC's advertised allowable values. `FullSpeedOverride` only applies when the standard boolean capability is present.

Before changes, the worker requires a usable hardware serial and healthy temperature/fan data, saves a recovery record and uses the current resource ETag when provided. It verifies the changed settings by reading them back. Stop/Exit restores original values and verifies them; failure retains the recovery record and blocks safe exit. Restarting the profile's monitor retries a pending recovery before new changes. HPE's own automatic thermal management remains active while its cooling policy/minimum is changed.

Use a trusted HTTPS certificate. Redirects and resource links to another host are rejected. This version requires one system/chassis per endpoint. Multi-node enclosures, firmware-specific policies and arbitrary OEM IPMI commands are not auto-enabled. Missing PC wall-power measurements remain unknown rather than being estimated by adding CPU/GPU watts.

## Windows startup

Setup enables **Start Thermal Ops when I sign in to Windows** by default. It creates a per-user Startup shortcut. Startup launches saved Dell control or the last selected native/local monitoring/control mode and hides the dashboard to the tray. Unconfigured Dell profiles remain stopped. Disable the entry in Windows Startup Apps or remove the Startup shortcut. Uninstall removes the shortcut and keeps profiles/history.

## Technology review sources

- HPE Redfish profiles: https://servermanagementportal.ext.hpe.com/docs/examples/redfishexamples
- Supermicro native fan modes: https://www.supermicro.com/en/support/manuals/product/software/redfish-user-guide-5-2/Content/general-content/bmc-configuration-examples.htm
- DMTF schema/property definitions: https://redfish.dmtf.org/schemas/DSP2053_2026.1.html
- Lenovo XCC2 fan resources: https://pubs.lenovo.com/xcc2-restapi/resource_fan
- Cisco thermal policies: https://netascode.cisco.com/docs/data_models/compute/intersight/organizations/policies/thermal_policy/
- Gigabyte Redfish: https://download.gigabyte.com/FileList/Manual/server_manual_redfish_v1.11.0.pdf
- ASRock controller utility: https://download.asrock.com/TSD/SMU/Manual/ASRock%20Rack%20Server%20Management_v2.8.0.pdf
- OpenBMC PID/zone design: https://github.com/openbmc/phosphor-pid-control
- Linux PWM/hwmon: https://github.com/torvalds/linux/blob/master/Documentation/hwmon/sysfs-interface.rst
- NVIDIA fan-control API/default restoration: https://docs.nvidia.com/deploy/nvml-api/latest/api/group__nvmlDeviceCommands.html
- Local Windows backend and API source: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/tree/v0.9.6
- Additional USB-controller ecosystem, reviewed but not integrated: https://github.com/liquidctl/liquidctl

## Bundled management tools

Version 1.2.2 includes the Windows IPMI runtime in Tools/IPMI and the HPE/iLO/Redfish backend. The built-in IPMI transport is selected by default. A custom executable can be selected by clearing Use built-in IPMI tool on Connection. No HPE CLI is required. Bundled IPMI was checked with a read-only live query; HPE remains validated by fixtures rather than physical hardware.
