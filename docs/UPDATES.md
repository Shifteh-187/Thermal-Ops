# Thermal Ops updates

The dashboard and tray menu include **Check for updates**. Startup checks are enabled by default and can be disabled in the tray menu. Offline/rate-limit failures during startup stay quiet; manual checks show an error and can be retried. There is no background installation.

The updater reads the public [GitHub latest-release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release) for `Shifteh-187/Thermal-Ops`. It compares numeric stable versions, ignores drafts/prereleases and refuses downgrades. Releases must include `Thermal-Ops-Setup-X.Y.Z.msi` and/or `.exe`, with the GitHub-generated SHA-256 asset digest. Assets must be at the expected release URL, have a positive size and be no larger than 256 MiB. Requests use HTTPS and timeouts; the installer is verified for exact size and checksum.

The MSI registry installation path identifies MSI installs. An Inno uninstaller beside the app identifies EXE installs. Portable/unrecognised installations open the release page. The updater never silently switches installer formats.

After the user chooses download, cooling continues while the file is fetched. After verification, a second prompt offers safe shutdown and installation. The existing shutdown dialog must acknowledge restoration before the helper is started. The helper waits up to two minutes for the dashboard process to exit, refuses to run while another detected dashboard/controller remains, checks the hash again and opens the normal installer wizard. Nothing kills a cooling process, restarts Windows or automatically resumes cooling. If setup is cancelled, reopen the app to resume configured startup profiles.

Downloads are stored under `%LocalAppData%\ThermalOps\Updates` in unique folders. Settings/profiles are handled by the existing installers and retained. Installers remain unsigned; a checksum checks download integrity against GitHub metadata, not a separate publisher signature.

Install 1.4.0 manually once to get this feature. Future release publishing should upload all matching installers before making the release public. Build both installers from the same version; MSI releases need a new ProductCode and the existing UpgradeCode.

## Validation

Run `Installer/Test-AppUpdates.ps1` for version/asset/format/integrity rejection fixtures, and `Installer/Test-UpdateHandoff.ps1` for a dummy installer handoff that verifies the parent exits first. The handoff fixture substitutes worker discovery only in the test build; the production helper includes the real process guard.

The 1.4.0 build also passed UI/bundle/tray and shutdown-acknowledgement checks, a real GitHub MSI download with digest verification, isolated MSI install/repair/uninstall tests, and a 1.3.0-to-1.4.0 MSI major upgrade preserving settings and the installation path. No production installer or fan-control write was executed by these checks.

## BETA releases

1.5.1 is flagged as a GitHub prerelease. The tray menu offers **Include BETA updates**, off by default. Opting in reads the public release list and selects the highest eligible numeric version, including prereleases; drafts are always excluded. Update prompts label prereleases BETA. Stable-only checks keep the latest-stable endpoint.

Versions before 1.5.1 cannot discover beta releases, so obtain this first beta directly from its release page. Numeric release tags and installer names remain vX.Y.Z; the GitHub prerelease flag and informational build version carry the beta status. Increment the numeric version for subsequent beta or stable builds.
