# Multi-server manager

**Add server** creates a saved profile with its own name, iDRAC address, username and password. Each server has a separate tab, connection page, cooling worker, status and log directory. Multiple supported R730 servers can run concurrently.

## Setup

1. Open `R730FanControl.exe`. The existing connection migrates into **Current R730** on first launch. All profiles start stopped.
2. Choose **Add server** and enter its name, iDRAC address and its own credentials. Other profiles' credentials are not copied into new profiles.
3. In that server's **Connection** page, check the local ipmitool path, select and confirm its GPU source, and save.
4. Use **Monitor only**, then **Start cooling** on its tab. Other workers continue independently.
5. **Stop all / Dell auto** restores every active live worker. Closing the manager requests the same graceful restoration and waits; failures are reported.

## GPU source

New profiles default to **Configure first** and cannot start until configured.

- **Local GPUs:** reads NVIDIA or a hardware-monitor provider on this Windows computer. The target FRU serial must match the Windows BIOS serial, preventing use of this computer's GPU temperature for another server. Your current R730 passed this check.
- **Server sensors only:** requires confirmation that the server has no chassis-cooled GPUs requiring monitoring. CPU, inlet, exhaust, additional exposed temperatures and six fan RPMs come from its own iDRAC. GPU exclusion is labelled on the dashboard.

Remote chassis-cooled GPU servers need an on-server controller with their own GPU telemetry. This release does not install a remote GPU agent or collect remote GPU temperatures. Do not use server-only mode to work around missing telemetry on a fanless GPU server.

## Model support and isolation

Profiles save independent connections and display detected models. Live commands still require a **Dell PowerEdge R730** and the tested sensor layout. Other models fail preflight before any fan writes. Multi-server support does not mean universal server compatibility.

Each `Profiles/<id>/settings.json` holds that server's credentials, with its password encrypted using Windows DPAPI for the current user. Logs and status are in its own `Runs` folder. These files are separate configurations, not separate OS security boundaries.

Duplicate normalized addresses are rejected. Live workers hold address and physical-identity locks, preventing two profiles controlling the same physical server through different addresses **on this Windows computer**. The locks do not coordinate controllers on different computers; run only one live controller per physical server across the network.

Profile removal requires a stopped worker and retains log folders. Editing a running connection is disabled. Stop, save and restart only that profile when changing credentials.

## Validation

Native build, UI self-test and visual layout pass. Profile checks verify independent usernames/passwords, settings paths, duplicate-address prevention and safe GPU defaults.

Two synthetic workers ran simultaneously with separate authentication. B failed, requested 100% and restored automatic control while A continued. A then stopped/restored independently. An alias profile for A's physical identity was rejected before raw writes. An unconfigured GPU source sent no raw commands. Server-only profiles made no local GPU calls.

Read-only inventory confirmed this computer's identity matches the existing R730. No additional real-server credentials have been supplied or used. No real server has been automatically enrolled into live control. The existing live app remains unchanged during development.

A full real-server read-only sample from the migrated Current R730 profile passed, including its GPU identity binding. The first attempt timed out on telemetry; a sequential retry succeeded. This does not validate additional physical servers.
