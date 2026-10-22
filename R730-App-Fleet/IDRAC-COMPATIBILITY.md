# Dell iDRAC compatibility — Thermal Ops 1.3.0

Support is decided per physical target. Identifying an iDRAC generation does not prove that undocumented raw fan commands are supported or that an R730 curve suits another chassis.

| Controller family | Typical server generation | Thermal Ops support |
|---|---|---|
| iDRAC6 | 11G, e.g. R610/R710 | IPMI monitoring where enabled; no raw fan control profile |
| iDRAC7 | 12G, e.g. R620/R720 | IPMI monitoring; try Dell Redfish discovery on firmware exposing the required resource |
| iDRAC8 | 13G, e.g. R630/R730/R730xd | General monitoring; recorded R730 fingerprint permits manual curves; other models/revisions remain read-only; Dell native minimum where exposed |
| iDRAC9 | 14G–16G, e.g. R740/R750/R760 | IPMI or Redfish monitoring; capability-dependent Dell minimum fan floor; no R730 raw commands |
| iDRAC10 | 17G | Redfish/IPMI monitoring when available; native minimum only if all required Dell attributes/limits are exposed; physical validation pending |
| Unknown/OEM/controller mismatch | Any | Monitoring only through the IPMI adapter; no model-name guessing to unlock writes |

The IPMI generation label is an expected family from an explicit model table. Unknown models remain Unknown. Some server configurations can use a different management controller. Redfish reports the BMC manager model and FirmwareVersion when available. IPMI `mc info` supplies a shorter firmware revision and auxiliary bytes; these are labelled as such and are not treated as the full iDRAC release number.

## Recorded manual-control combination

The current allowlist contains **Dell PowerEdge R730**, manufacturer ID **674**, product ID **256**, IPMI firmware revision **2.86**, auxiliary bytes **00065656**. This fingerprint was read from the existing R730 deployment. It preserves that deployment's established manual-control path; it is not certification of every configuration sharing those identifiers. The full original R730 sensor checks, GPU identity checks, startup floor, temperature thresholds, duplicate-target lock and restoration path still apply.

Other firmware, missing firmware metadata, R730xd and other models do not receive raw fan commands, including cleanup commands, from an unsupported live request. They continue monitoring. The standalone R730 console rejects an unsupported live request instead.

## Dell Redfish minimum fan floor

Select **Dell iDRAC (Redfish fan minimum)** when adding a server. The worker checks Dell manufacturer identity and reads `/redfish/v1/Managers/System.Embedded.1/Attributes`. It requires the DellAttributes type and numeric `ThermalSettings.1.MinimumFanSpeed`, `MFSMinimumLimit` and `MFSMaximumLimit` values. Missing, ambiguous or invalid limits disable this path. The requested floor must be inside those bounds and must not lower an existing custom floor. Original value 255 means no user minimum and is preserved for restoration.

This is a fan floor, not a fixed speed or custom temperature curve. Dell can increase fans above it. No thermal profile, PCIe response, maximum exhaust limit or arbitrary OEM attribute is modified. Changes require healthy sensor data, a usable hardware serial, saved recovery data and successful read-back. Stop restores the original setting and verifies it; failed recovery remains visible and retains its record. An abrupt process/OS failure cannot execute cleanup; restarting the profile retries pending recovery.

The adapter uses exposed capabilities instead of a blanket firmware cutoff. Dell's official scripting project lists minimum Redfish firmware of 2.40.40.40 for iDRAC7/8, 3.00.00.00 for iDRAC9 and 1.10.17.00 for iDRAC10. Those are API entry points, not a promise that every listed version exposes writable thermal attributes. Trusted HTTPS and the appropriate iDRAC permissions are required. No certificate bypass or firmware downgrade is built in.

## Contributing a hardware report

Use **Hardware support request** after a monitoring scan. Review, copy and paste into the GitHub hardware issue template. Reports contain selected inventory/capability fields and sensor readings, never the saved profile or raw command output. They help determine what to investigate; actual model-specific sensor validation, cooling response and restoration testing are still required before adding another manual-control combination.

## Primary sources reviewed

- [Dell server generation/controller table](https://www.dell.com/support/kbdoc/en-td/000137343/how-to-identify-which-generation-your-dell-poweredge-server-belongs-to)
- [Dell official Redfish scripting project and firmware prerequisites](https://github.com/dell/iDRAC-Redfish-Scripting)
- [DellAttributes resource/API guide](https://www.dell.com/support/manuals/en-us/idrac9-lifecycle-controller-v3.3-series/idrac_3.31.31.31_redfishapiguide/dellattributes?guid=guid-15d2a851-df64-4ef2-af34-10d2f373807d&lang=en-us)
- [Dell iDRAC9 minimum fan bounds and 255 semantics](https://dl.dell.com/topicspdf/idrac_3_31_ug_en-us.pdf)
- [Dell iDRAC7/8 thermal settings](https://dl.dell.com/topicspdf/idrac7-8-lifecycle-controller-v2505050_users-guide_en-us.pdf)
- [Dell iDRAC10 thermal settings](https://www.dell.com/support/manuals/en-us/idrac10-lifecycle-controller-v2-xx-series/idrac10_1.20.xx_ug/modifying-thermal-settings-using-racadm?guid=guid-7973c3ea-5849-4b18-ad9a-02e8a7f41bd9&lang=en-us)

Validation: automated fixtures cover unsupported raw-control rejection, variable sensor inventories, Dell minimum bounds, patch validation, read-back, original-setting restoration and failed-recovery retention. Other physical iDRAC generations remain untested.
