# Changelog

## 1.5.0 - Fan curve editor, cluster and hardware discovery

- Remove View live feed and replace the Smart trial checkbox with a third Fan curves tab.
- Add point-graph editing, protected manual duty, automatic detected fan/sensor lists and persisted per-server settings.
- Add atomic server-name editing while retaining the profile identity, credentials and history.
- Rename visible Fleet labels to Cluster and buffer graph/tab rendering; update cluster rows in place.
- Add explicit read-only discovery with progress, sensor/device/query tabs, IPMI/Redfish and local-PC backends, and filtered public reports.
- Record conflicting individual R730xd fan-control evidence; keep unverified per-fan writes disabled.
- Embed the author's requested decompiler/source-reader note as a public constant.

## 1.4.1 - Dell reconnect and hardware query locators

- Preserve the original exit reason alongside Dell automatic-restoration status.
- Retry owned Dell IPMI telemetry/command failures with a capped delay; Stop, Exit and upgrade shutdown cancel retries.
- Require three complete samples before takeover and retain a pending Dell restoration marker on unsuccessful recovery.
- Keep fan stall/response, identity, ownership and configuration faults stopped for review.
- Add IPMI SDR sensor number/entity ID discovery, successfully read Redfish paths and available local sensor identifiers to support reports.
- Show the actual app version, sensor units/status and report unavailable discovery explicitly.

## 1.4.0 - GitHub updater

- Startup update check with tray opt-out, plus dashboard/tray manual checks.
- Stable-version comparison and installer selection matching the installed MSI or EXE edition.
- Bounded downloads with SHA-256 verification before and after shutdown.
- Explicit upgrade choice, existing cooling restoration checks and delayed installer launch after app exit.
- Portable installations open the release page; no automatic format conversion or forced restarts.

## 1.3.0 MSI packaging

- Added a full native per-user MSI with optional desktop/startup shortcuts.
- Installation and removal block while cooling workers are active; saved settings and profiles are retained.
- Separate EXE/MSI migration guard, reproducible MSI build scripts and isolated installation tests.

## 1.3.0 - broader iDRAC discovery and support requests

- Generic Dell IPMI monitoring for different fan/CPU inventories and missing sensors.
- Model, firmware and controller fingerprint gate before any R730 raw fan writes.
- Dell Redfish minimum-fan control with firmware bounds, read-back and original-setting recovery.
- Hardware support request preview/copy button and GitHub issue template; private connection fields excluded.
- Dashboard screenshot and multiple-server/fan-farm setup guidance.
- Redfish incomplete/zero-fan telemetry prevents new native control.

## 1.2.2 - initial public release

- Windows dashboard, independent server profiles, fleet health and temperature/power history.
- R730 cooling controller and preserved console versions with original thresholds.
- Capability-dependent Redfish/HPE adapters and local PC sensor/fan discovery.
- Bundled IPMI transport, tray operation, startup integration and orderly cooling shutdown.
- Public source uses local connection settings and excludes deployment credentials and telemetry.
