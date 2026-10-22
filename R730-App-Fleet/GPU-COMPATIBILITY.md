# GPU compatibility

This update removes the single-model assumption. The six R730 chassis fans follow the hottest monitored GPU core, while CPU, exhaust, emergency and fan-health safeguards remain in force. Existing R730 curves and the GPU 83 C / 72 C emergency latch are unchanged. Broad telemetry compatibility does not certify a card's airflow, power wiring or suitability for this chassis.

| Cards | Telemetry route | Requirements / verification |
|---|---|---|
| NVIDIA GeForce GTX/RTX, NVIDIA RTX/Quadro, Tesla and other NVIDIA devices | Native `nvidia-smi` | Installed driver/tool must expose UUID and core temperature for each card. RTX 3060 tested physically; other families depend on driver/card capabilities. |
| AMD Radeon, Radeon Pro and other exposed AMD GPUs | LibreHardwareMonitor WMI; legacy OpenHardwareMonitor accepted | A working monitor must expose GPU hardware identity and a named core-temperature sensor. AMD readings tested with synthetic fixtures, not physical AMD hardware here. |
| Intel Arc and exposed Intel integrated GPUs | LibreHardwareMonitor WMI | Same requirements; Intel readings tested with synthetic fixtures, not physical Intel hardware here. Legacy OpenHardwareMonitor builds may lack Intel GPU support. |
| Mixed vendors / multiple cards | Auto combines native NVIDIA with a monitor's AMD/Intel data | Every detected supported-vendor display adapter must have temperature coverage. All cards share chassis cooling. |

## Setup

On NVIDIA systems, keep the default **Auto** provider. Existing settings migrate without changing credentials or cooling thresholds.

For AMD or Intel, run [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) with working WMI publishing before starting cooling. Select Auto, or select its provider explicitly in Connection and save. This application reads an existing provider; it does not bundle or install LibreHardwareMonitor, its drivers or a service. Some monitor releases/configurations have WMI issues, so a running monitor window alone is not proof of usable telemetry. Preflight requires actual hardware and core-temperature rows.

The supported namespaces are `root\LibreHardwareMonitor` and `root\OpenHardwareMonitor`, using their `Hardware` and `Sensor` classes. Their actual field definitions are documented in [LibreHardwareMonitor's hardware WMI implementation](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/blob/v0.9.4/LibreHardwareMonitor/WMI/Hardware.cs) and the [OpenHardwareMonitor WMI specification](https://openhardwaremonitor.org/wordpress/wp-content/uploads/2011/04/OpenHardwareMonitor-WMI.pdf). NVIDIA querying follows its [official nvidia-smi documentation](https://docs.nvidia.com/deploy/nvidia-smi/index.html).

**Overview** displays every monitored card with its source, core temperature, load, power and identity. Missing optional readings display `--`. The Overview GPU value is the maximum core temperature across cards; load and power summaries are independent maxima, not a synthetic single GPU.

## Safety and limits

- Core temperature and identity are required. Missing or invalid values stop custom control and trigger the existing fault/recovery path if live takeover was attempted.
- Power and utilisation are optional. If either is unavailable for any card, preserve missing values, hold at least 55% chassis command and refresh the post-load hold. Emergency demand still goes straight to 100%.
- Core, memory-junction and hotspot temperatures have different meanings. This adapter deliberately requires a recognisable core sensor and does not substitute memory or hotspot readings. Those extra temperatures are not yet monitored as separate protection channels.
- Source selection is fixed for each run. A failed provider never silently drops its cards or switches to a different source after takeover.
- NVIDIA UUIDs detect card replacement even when the number of cards stays the same. Monitor identity uses its hardware identifier plus model name; it is not a hardware serial and cannot guarantee detection of replacement by the same model in the same slot.
- Auto checks PCI display-adapter counts for NVIDIA/AMD/Intel against telemetry each cycle. Dell's Matrox management display is not treated as a heat-producing add-in GPU target. Compute-only devices invisible to Windows `Win32_VideoController` cannot be guaranteed by this coverage check; NVIDIA's own enumerated devices are still included.
- Explicit provider selection scopes monitoring to cards exposed by that provider. Use Auto for mixed vendors and avoid running several live fan controllers.
- WMI publishing has no universal per-sample freshness timestamp. The app detects query/provider/card failures but cannot prove that a hung third-party provider is refreshing otherwise plausible values. NVIDIA direct queries avoid this particular dependency.
- Existing IPMI acquisition latency remains; this does not make the R730 thermal response instantaneous.

## Validation

19 synthetic provider checks cover NVIDIA optional values and parsing, malformed/missing core readings, duplicate IDs, same-count identity replacement, AMD/Intel sensor mapping, core-versus-memory semantics, coverage, mixed native/monitor routing, disconnects and the actual conservative cooling floor/emergency behaviour.

Five fake-hardware integration scenarios cover read-only mode, live lifecycle, fault cooling, failed restoration and graceful stop. UI rendering and native configuration self-tests pass. Two full real-server read-only samples succeeded with an RTX 3060. Only the RTX 3060 has physical validation in this environment; the other adapters are implemented and fixture-tested, not claimed as universally tested hardware.
