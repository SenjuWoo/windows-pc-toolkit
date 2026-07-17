# PC Corruption Fixer v6.3

## What's New in v6.3
- **Sleep-free long repairs** — SFC, DISM, Full Repair, and Windows Update repair call `SetThreadExecutionState` so modern standby cannot suspend the PC mid-scan. Stay-awake is always released on exit.
- **DoH-aware Network Diagnostics [14]** — reports `EnableAutoDoh` and registered DNS-over-HTTPS templates (Quad9 / Mullvad HTTPS tunnels).
- **Cleaner TCP probes** — `TcpClient` is disposed properly after connectivity tests.

## What's New in v6.2
- **Remove AI Bloat [23]** — disables Windows Copilot (service, scheduled tasks, AppX package, policies), Windows Recall (AI screenshot/timeline), Windows AI features (Paint/Photos AI, data analysis), Edge Copilot (page context, CDP, AI themes), Chrome AI/genAI, Cortana/Bing web search, AI-powered cloud search. Reports all actions with per-item status.

## What's New in v6.1
- **Fix Performance Counters [21]** — rebuilds the perf counter registry (`lodctr /R`, 64- and 32-bit) and resyncs WMI. Fixes Perflib errors in Event Log and broken Performance Monitor / Task Manager graphs.
- **Orphaned Service Cleanup [22]** — scans every service for a program that no longer exists on disk (dead leftovers from uninstalled apps that error at every boot) and optionally removes them, asking per service.
- **Service check no longer cries wolf** — demand-start services like BITS sit stopped by design; they're now shown as `Stopped (starts on demand)` instead of being flagged and force-started.

Advanced one-click system repair toolkit for Windows 10/11. Fixes corrupted system files, repairs Windows Update, clears caches safely, resets networking, deep-cleans components, checks disk health, diagnoses network/driver/disk-space problems, and exports a styled HTML health report. All operations are logged with full transparency.

## What's New in v6.0

### Security Hardening
- **Binary-planting immunity** — Every system tool (`sfc`, `DISM`, `chkdsk`, `netsh`, `regsvr32`, `w32tm`, …) is now resolved to its **absolute path inside `C:\Windows\System32`** before running. Previously tools were invoked by bare name through `cmd.exe`, which searches the current directory first — so a malicious `sfc.exe` dropped next to the script (e.g. on a shared USB stick) could have run with Administrator rights. That entire class of attack is now closed; a rogue executable in the script folder is never executed.
- **No more `cmd.exe` middleman** — Executables are launched directly with an explicit argument array, removing the command-injection surface of string concatenation.
- **DLL re-registration hardened** — Windows Update DLLs are registered by absolute System32 path (bare-name `regsvr32` also searches the current directory).
- **Launcher hardened** — `Fix_Corruption.bat` now calls PowerShell by its absolute System32 path instead of relying on `PATH`.

### Fixes (found via real run logs)
- **SFC output no longer mangled** — sfc.exe emits UTF-16; the console encoding is now switched during the call, so logs show `Verification 42% complete` instead of `V e r i f i c a t i o n …`, and duplicate progress lines are collapsed.
- **No more stray `ExitCode Output` tables** — internal result objects no longer leak into the console/log during Cache Cleanup, Network Reset, and Deep Cleanup.
- **CHKDSK "Access is denied" handled** — falls back to `Repair-Volume -Scan` (different code path that usually succeeds) instead of just failing.
- **CBS.log tailed, not slurped** — the log (often hundreds of MB) is read with `-Tail` instead of loading it all into RAM.
- **WSReset removed from Clear Caches** — the Store window no longer pops open mid-cleanup (it's part of Store Reset only).
- **Firewall reset is now opt-in** — resetting the firewall deletes all custom rules (VPN/game/app rules), so it asks first; Full Repair skips it entirely to stay unattended.
- Duplicate firewall entry removed from the service checklist; deliberately **disabled** services are reported but no longer force-restarted; Quick Health Scan service check logic fixed.

### New Features (8)
- **Windows Update Health Check [13]** — read-only: services, update history, pending reboot, disk space, TCP connectivity to update servers.
- **Network Diagnostics [14]** — read-only: adapters, IP/gateway/DNS config, gateway ping, internet ping, DNS resolution, HTTPS test.
- **Rebuild Icon & Thumbnail Cache [15]** — fixes blank/black/wrong icons (restarts Explorer safely).
- **Repair Time Sync [16]** — starts/repairs the Windows Time service and forces a resync; re-registers the service if needed. A wrong clock breaks HTTPS and updates.
- **Problem Device Scan [17]** — read-only: lists devices reporting driver/hardware errors with plain-English explanations of each error code.
- **Disk Space Analyzer [18]** — read-only: measures known space hogs (temp, WU cache, Windows.old, hiberfil.sys, Recycle Bin, WinSxS, …) with cleanup tips.
- **Startup Programs Viewer [19]** — read-only: everything that launches at sign-in (registry Run/RunOnce + Startup folders), flagging anything running from a TEMP folder.
- **Export HTML Health Report [20]** — dark-themed report (system, drives, services, event logs, session results) saved to Desktop and opened in your browser.

### Improvements
- Dashboard now shows **usage bars** for disk and RAM.
- Windows Update repair also handles **Delivery Optimization / Update Orchestrator** services and **warns if an update is mid-install** (pending reboot) before resetting.
- Old logs are **auto-pruned** (newest 15 kept on the Desktop).
- Temp cleanup reports **MB freed**, handles files with brackets in their names, and no longer triple-enumerates the folder.
- Elapsed/session times format correctly past one hour.
- Menu reorganized into categories: System Repair, Windows Update & Store, Diagnose (read-only), More Tools.

## Full Feature List

| # | Feature | Description |
|---|---------|-------------|
| 1 | **Full Repair** | SFC + DISM + Caches + Network + Disk (restore point offered; runs unattended) |
| 2 | **SFC & DISM Repair** | System file check + component store repair with CBS log analysis |
| 3 | **Clear Caches (Safe)** | DNS, Temp, Thumbnails, Recycle Bin, Delivery Optimization — preserves Update data |
| 4 | **Network Stack Reset** | IP release/renew, Winsock, TCP/IP, DNS; firewall reset is opt-in |
| 5 | **DISM Deep Cleanup** | Component store analysis + cleanup (ResetBase is opt-in with warning) |
| 6 | **CHKDSK Disk Check** | Online scan for C: with Repair-Volume fallback |
| 7 | **Repair Windows Update** | Safe WU component reset (rename, re-register, restart) |
| 8 | **System Restore Point** | Create a named restore snapshot |
| 9 | **Service Health Check** | Verify critical services, restart stopped ones (respects disabled) |
| 10 | **Store App Reset** | WSReset + full AppX re-registration |
| 11 | **Event Log Scan** | 72-hour System + Application error/critical scan |
| 12 | **Quick Health Scan** | Read-only multi-area system diagnostics |
| 13 | **WU Health Check** | Read-only Windows Update diagnostics |
| 14 | **Network Diagnostics** | Read-only connectivity tests |
| 15 | **Icon Cache Rebuild** | Fix blank/wrong icons and thumbnails |
| 16 | **Time Sync Repair** | Fix system clock synchronization |
| 17 | **Problem Device Scan** | Read-only driver/device error report |
| 18 | **Disk Space Analyzer** | Read-only "what's eating my disk" report |
| 19 | **Startup Viewer** | Read-only sign-in autostart listing |
| 20 | **HTML Health Report** | Styled report exported to Desktop |
| 21 | **Fix Performance Counters** | Rebuild counter registry + WMI resync |
| 22 | **Orphaned Service Cleanup** | Find/remove services from uninstalled apps |
| 23 | **Remove AI Bloat** | Windows Copilot, Recall, AI features, Edge/Chrome AI |

## How to Use

### Batch File (Recommended)
1. **Double-click `Fix_Corruption.bat`**
2. Click **"Yes"** on the UAC prompt
3. Select a menu option and follow the prompts
4. **Restart your PC** when done (if prompted)

### Direct PowerShell
1. Right-click **`PC_Fixer.ps1`** → **Run with PowerShell** (as Administrator)
2. Use the interactive menu to select operations
3. Review the log on your Desktop if needed

## Dashboard Info

The startup dashboard shows CPU, OS build, uptime, C: drive free space and RAM (with usage bars), Defender status and definition age, Windows Update service status, active network adapters, and pending-reboot detection with reasons.

## Requirements

- Windows 10 or 11
- Administrator rights (auto-requested by both launchers)
- Internet connection (for DISM repairs and connectivity tests)
- 5–60 minutes depending on selected operations

## Safety

- Only official Microsoft tools — resolved to their **absolute System32 paths** so nothing in the script folder can ever be executed (safe to run from a USB stick)
- No third-party software, no registry hacks
- **Windows Update data is preserved**; WU repair refuses to run mid-install without confirmation
- Firewall reset and DISM ResetBase are **opt-in** with clear warnings (both default to No)
- System Restore Point offered before destructive operations
- Read-only diagnostics are clearly marked and change nothing
- All actions are logged to the Desktop (newest 15 logs kept)

## Files

| File | Purpose |
|---|---|
| `PC_Fixer.ps1` | Main PowerShell script with all repair functions |
| `Fix_Corruption.bat` | Batch launcher — self-elevates and launches the PS1 |
| `README.md` | This file |
| `validate_syntax.ps1` | Syntax checker for the PowerShell script (portable) |

## For Sharing

Copy the entire `Pc Corruption Fixer` folder to a USB drive or share via cloud. Works on any Windows 10/11 PC — and as of v6.0 it's safe even if something malicious lands in the same folder.
