# PC Privacy Guard v1.0.1

**Location mask · Tracker kill · Safe for games, browsers, Windows Update**

Standalone privacy toolkit that lives next to **PC Gaming Optimizer**, **PC Corruption Fixer**, and the **Encrypted DNS** scripts. It focuses on **hiding/disabling Windows location** and killing **OS-level trackers** without breaking gaming, browsing, or updates.

## v1.0.1 fixes
- **`[0] EXIT` works** — PowerShell `break` inside `switch` only left the switch; menu now uses an explicit exit flag.
- **No more `True`/`False` spam** after every registry/service write (helpers no longer emit bools to the pipeline).
- **TrkWks** (Distributed Link Tracking): falls back to `Set-Service` when the service key denies direct registry writes.

## Quick start

1. Double-click **`Run_As_Admin.bat`** → Yes on UAC  
2. Prefer **`[A] FULL PRIVACY LOCKDOWN`** (offers a restore point)  
3. Restart when finished  

## What it does

| Module | Effect |
|--------|--------|
| **Location kill** | Disables `lfsvc`, LocationAndSensors policies, Find My Device, MapsBroker, Wi‑Fi Sense residuals |
| **App capability** | Sets ConsentStore **location = Deny** (user + system + NonPackaged) |
| **Clear caches** | Wipes known location-provider folders + per-app location grants |
| **Advertising** | Advertising ID off, Start suggestions / tailored experiences off |
| **Activity** | Timeline/activity **upload** off, cloud content soft-landing off, cross-device clipboard off |
| **Telemetry** | **Level 1 only** (Required), DiagTrack + dmwappush disabled, CEIP tasks off, DoSvc **kept** HTTP-only |
| **Input / speech** | Inking/typing harvest off, online speech off, web search in Start off (local search works) |
| **Browsers** | Edge/Chrome/Firefox **policies** for metrics/Copilot/prediction only — browsing still works |

## What it deliberately does **NOT** touch

| Preserved | Why |
|-----------|-----|
| **Windows Update** (`wuauserv`, `UsoSvc`) | Updates must keep working |
| **Delivery Optimization** (`DoSvc`) | Required by WU / Store / DISM — only P2P sharing disabled |
| **BITS**, CryptSvc, Store | Download / signature / Store stack |
| **Xbox / Game Bar services** | PC Game Pass, overlay, networking |
| **Browsers themselves** | No homepage hijack, no extension kill, no proxy force |
| **Camera / Microphone** | Discord, game chat, Meet/Zoom still work |
| **Firewall, DNS Client, Audio, GPU** | Gaming + network stability |
| **Telemetry Level 0** | Never used — Level 0 breaks WU health checks and DISM |

## Menu

```
[A] Full Privacy Lockdown (all safe modules)
[1] Kill location services & policies
[2] Deny app location capability
[3] Clear location / sensor history caches
[4] Advertising ID + tailored experiences
[5] Activity history / timeline upload
[6] Telemetry trackers (WU-safe Level 1)
[7] Input / speech / cloud search trackers
[8] Edge/Chrome privacy policies
[S] Refresh status dashboard
[R] System Restore Point
[U] Undo Privacy Guard changes
[0] Exit
```

## IP location vs Windows location

This app stops **Windows and apps** from using the OS geolocation stack (GPS/Wi‑Fi AP / cell-style location APIs).

Websites can still **guess country/city from your public IP**. For that layer use:

1. **Encrypted DNS** — `DNS_Set_Quad9_Mullvad.bat` (DoH HTTPS) in the parent folder  
2. A **VPN** if you need to hide the IP itself  

## Undo

Menu **`[U]`** reverts services, ConsentStore location, and policy trees this app owns. Restart afterward. You can also use the restore point created at lockdown.

## Files

| File | Purpose |
|------|---------|
| `PC_Privacy.ps1` | Main interactive app |
| `Run_As_Admin.bat` | Elevating launcher (absolute System32 PowerShell) |
| `validate_syntax.ps1` | Syntax checker |
| `README.md` | This file |

## Safety notes

- Run as Administrator only via the bat launcher  
- Log written to Desktop: `PC_Privacy_Log_*.txt`  
- Compatible with **PC Gaming Optimizer** (overlaps on DiagTrack/ads are intentional and WU-safe)  
- Does **not** install third-party software or download anything  

## License

Free to use, modify, and share.
