# Changelog

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
