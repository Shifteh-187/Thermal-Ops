# Controller exit reasons and reconnection

The Dell IPMI worker in 1.4.1 retains `ExitReason`, `FailureMessage`, `RetryAllowed`, `RequestedLive` and `StopRequested` in its final status, independently of the automatic-cooling restoration result. Activity records the original reason. The reconnect countdown also shows it. Earlier versions could replace the fault message with the successful restoration message.

| Reason | Examples | Behaviour |
| --- | --- | --- |
| TelemetryUnavailable | Required CPU/inlet/exhaust reading missing, changed sensor inventory, unavailable GPU telemetry, freshness budget exceeded, initial identity read unavailable | Restore Dell auto, retry with delay; validate identity and three consecutive complete samples before takeover |
| ConnectionOrCommandFailure | IPMI command timed out or returned a nonzero exit code | Restore Dell auto where possible, retry with delay; persistent credential/transport errors continue to be reported |
| HardwareSafetyFault | Fan missing/stalled, unhealthy reported sensor, a sustained substantial RPM drop after a settled fan increase | Restore Dell auto; user investigation required before a new start |
| ConfigurationOrUnexpectedFault | Invalid configuration, conflicting controller ownership, identity mismatch, unknown exception | Remain stopped; user investigation required |
| UserStop | Explicit stop file or dashboard Stop | No reconnect |
| Completed | Finite test session completed | No reconnect |
| Missing final status / unknown worker crash | No reliable structured exit record | Remain stopped; check Activity |

Retry delays are 10, 20, 40, 80, 160 and then 300 seconds, capped at 300. A valid normal/monitoring session lasting at least 60 seconds resets the delay. Each attempt rechecks identity, firmware compatibility, physical-server ownership and complete sensor inventory. Recovery never bypasses the existing hardware gate or temperature curves. A persistent pending marker is bound to the management endpoint and hardware serial, and requires an accepted Dell automatic-mode command before a subsequent takeover after failed restoration or interrupted control.

**Stop / Dell auto** and **Stop all** cancel a pending retry and turn off that profile's automatic start preference. Exit and upgrade shutdown cancel pending retries for the current app session while retaining the existing startup preferences. A failed restoration remains visible and blocks normal safe exit until addressed. Reconnection is supervised by the running dashboard and applies to its Dell IPMI workers. External feed viewers, standalone console scripts, local-controller workers and Redfish workers are not automatically restarted by this change; they have different recovery semantics.

The 1.4.1 recovery tests use a fake executable transport. They verify missing telemetry, three complete samples before the first manual command, automatic-mode restoration, retained fault metadata, parsed SDR identifiers, retry backoff/cancellation and rejection of hardware/ownership/unknown faults. No production controller or physical fan command is used by these tests.

## 1.5.1 BETA RPM response correction

A missing 5% RPM rise alone is no longer a hardware-fault stop: fans may already be fast, and duty percentages are requests rather than measured PWM. A rise test only starts after a 90-second startup grace and at least 30 seconds at the previous requested duty, then observes the sustained increase for 30 seconds. Retargeting cancels the old test. Flat positive RPM is reported as unconfirmed. A greater-than-20% RPM drop must persist for three post-deadline samples before faulting; missing/stalled fans and unhealthy sensor reports still stop control immediately. This does not require or perform a full-speed calibration.
