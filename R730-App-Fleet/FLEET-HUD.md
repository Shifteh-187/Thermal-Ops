# Fleet health HUD and power graphs

## Layout

**All Servers** is the starting page: overall telemetry health, total known server input power, reporting coverage, attention/setup/stale counts and a per-server table. Double-click a row to open that server. The table includes model, controller state, GPU/CPU temperature, input watts, fan command, sample age and active curve mode.

Each server's **Overview** groups key readings above side-by-side temperature and power graphs. GPU details, fan RPMs and exposed temperature probes remain below on the same scrolling page. Both graphs have independently selectable ranges from one minute to 24 hours and saved per-profile/per-target history.

## Health meaning

Green means the available controller telemetry is fresh and nominal. It is not a full hardware diagnosis. Missing required temperatures/fan readings, stale feeds, configuration gaps and controller alerts cannot be presented as healthy. Faults, emergency thresholds and stalled fans require attention; unavailable or unmonitored servers remain unknown/setup-required.

## Power meaning

- The HUD sums **fresh reported server input watts**, with a count such as `1 / 2 servers reporting`.
- Missing, stale, future-clock and wrong-target readings are excluded rather than replaced with zero. A partial sum is labelled **KNOWN INPUT / PARTIAL**, not a complete fleet total.
- Duplicate normalized endpoint addresses are not counted twice. Different DNS/IP aliases cannot be merged reliably without a shared hardware identifier in the status feed; avoid saving duplicate aliases as separate monitoring targets.
- Each server's power graph shows **server input** and **GPU sum (subset)**. GPU power is already included in server input; never add the two traces together.
- GPU sum is shown only when all monitored GPUs report numeric power. Missing board power or GPU power leaves gaps; no values are invented.
- This is instantaneous power in watts, not energy in kWh or an electricity-cost estimate. The readings are last-reported samples and are not guaranteed simultaneous across servers.

## Current deployment

The new HUD is opened read-only against the existing controller feed. The original manager continues running smart curves. `VIEW ONLY` and `Stop viewing` identify the non-controlling view. Starting/stopping a view does not stop its external controller. All Servers can also display cached feeds explicitly linked to saved profiles; such files do not cause network probes or fan commands.

The cooling worker and smart-curve code are unchanged. No additional server is started automatically. To move live control into this build, perform a separate graceful handover after stopping the existing worker.

## Validation

Native build, UI/profile self-tests and rendering of both pages pass. Tests cover fresh/stale/missing/wrong-target power, partial totals, duplicate endpoint aggregation, complete versus incomplete GPU sums, power values above temperature ranges, negative-power rejection, missing-fan health and the existing graph time/gap/history rules. Real R730 board/GPU power is read from the existing feed.

Total fleet power graph: selectable period; full fresh coverage required, with gaps for missing data. View live feed automatically locates fresh matching local server telemetry without a file picker.

Tray: X hides the dashboard and keeps cooling running. Double-click the tray icon or choose Dashboard to reopen. Tray menu also provides Add server and Exit / restore Dell auto. Exit gracefully stops only workers owned by this window.

Safe Exit: opens a progress dialog, gracefully signals owned or attached local controllers to stop, waits for a fresh final report that iDRAC accepted Dell automatic control, and blocks Exit on failure or unknown outcome. Read-only monitors are identified separately. No hardware mode read-back is claimed. Keep dashboard open does not cancel a stop already requested.

Normal launch automatically starts configured servers with confirmed GPU sources, keeping identity and telemetry checks before takeover. An existing fresh local feed is attached instead of starting a duplicate controller. Saved Smart selection is restored; newly added unconfigured servers remain stopped. Preview, tests and explicit observe launches do not auto-start.
