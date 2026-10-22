# Live temperature graph

Each server's Overview has a terminal-style **THERMAL TRACE** chart: dark grid, neon traces, selectable **1 minute, 5 minutes, 15 minutes, 30 minutes, 1 hour, 6 hours or 24 hours**. Default is five minutes. Use the coloured checkboxes to show/hide GPU maximum, CPU maximum, exhaust, inlet and additional-system maximum. Hover over the plot to inspect the nearest real sample.

The graph records actual controller timestamps, not one-second fabricated readings. This R730 typically takes about 20–30 seconds to collect telemetry. The display refreshes every second, but new points arrive only when the controller supplies a new sample. More than 45 seconds without a sample is labelled stale. Long gaps, missing sensors and new sessions are not joined by a line.

History is saved separately for each server profile and target address, retaining up to 24 hours / 50,000 samples. Earlier periods remain empty until enough data has been collected. Changing the displayed range does not change fan control. Overview scrolls to keep the full graph, GPU table, all six fans and temperature-probe table on one page.

**View live feed** can follow an existing controller's status JSON without sending IPMI commands. The target must match the selected profile. This shows **VIEW ONLY**, and **Stop viewing** ends only the view; the external controller continues. Normal **Monitor only** and **Start cooling** use this app's own worker as before. Global Stop all stops owned workers and ends views; it does not stop an external controller through a view.

Validation: native build and visual checks; history tests for selectable windows, duplicate/out-of-order/future timestamps, missing values, long gaps, session boundaries, file round-trip/corrupt-line recovery and retention. Real R730 samples were recorded through the view. The cooling engine is byte-for-byte unchanged from the multi-server build.

On the requested restart, the R730 worker restored Dell automatic control, then the graph manager reopened with only Current R730 requested to resume. The additional saved profile was preserved and left stopped.
