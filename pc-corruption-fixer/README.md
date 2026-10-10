# PC Corruption Fixer 7.2.1

Official Windows repair and diagnostics with logs, explicit advanced choices and retained backups. Use [Repair & tools in the dashboard](../README.md) or `Fix_Corruption.bat`. Keep the complete toolkit extracted together.

## Repair workflow

The dashboard runs **DISM /RestoreHealth → SFC /scannow**, saves native output and exit codes, blocks pending update restarts and never forces reboot. This follows [Microsoft's repair sequence](https://support.microsoft.com/en-us/topic/use-the-system-file-checker-tool-to-repair-missing-or-corrupted-system-files-79aa86cb-ca52-166a-92a3-966e85d4094e).

The console's Full Repair adds guarded aged-temp/cache cleanup, DNS cache/connectivity refresh and online disk checks. It does not reset Winsock/TCP/IP/firewall or alter adapter DNS. SFC's actual output supplies the corruption verdict; no guessed numeric exit mapping claims files were repaired. SFC is deferred if DISM fails or needs a restart. Component cleanup also waits for pending update/servicing restarts, and DISM runs with `/NoRestart`.

## Windows Update repair

Run only for an update fault, from the explicit console option. Pending servicing/update restarts block it. It records service states, requires every relevant service to stop before touching caches, retains timestamped SoftwareDistribution/catroot2 folders, checks each rename and restores originally running services in `finally`. Stopped services stay stopped; startup types are not changed. Stop/restart/partial-cache failures are reported as needing attention. A rebuilt cache is not proof a subsequent update succeeds. Check Windows Update afterward. Local visible update history may be rebuilt; installed updates remain installed.

## Network and advanced tools

Explicit Winsock reset is separate from Full Repair. Deeper TCP/IP reset needs its own confirmation because it can remove custom adapter configuration. Network backups abort on unreadable DNS/DoH state; restore uses adapter GUIDs and separately verifies IPv4/IPv6 automatic/static modes and existing DoH templates.

Other console tools: disk scan, Store/AppX repair, event logs, service/driver/startup diagnostics, time sync, disk-space analysis, performance counters, HTML report and reversible AI/browser privacy policies. AI policy support depends on Windows edition/build and browser version. Policies can delete Recall snapshots and browser built-in models; undo restores policy values, not deleted data. Use the dashboard for modern Copilot app removal and checked Recall feature disabling. ResetBase, service removal, strict policies and other advanced operations are separate choices.

Store registration repair uses packages already installed for the current account. It does not register another user's apps into your account. A failed time resync preserves your existing NTP/domain configuration. Orphan-service deletion requires a stopped service and a confirmed missing `.exe` on a ready local fixed drive; disconnected/network paths and access failures are not treated as missing programs.

Warnings/errors are logged to `%LOCALAPPDATA%\WindowsPCToolkit\Logs\PCFixer\PCFixer.log`, with version and cause. For detailed transcripts and configuration/state diagnostics, launch `PC_Fixer.ps1 -DebugLog` or set `WINDOWS_PC_TOOLKIT_DEBUG=1` for the launching process. Debug logging is off by default. JSONL diagnostics rotate at 2 MB; at most 15 debug transcripts are retained. HTML reports use the same log folder. Network/AI/service backups are under `%ProgramData%\WindowsPCToolkit\PCFixer`. Dashboard repair reports are in `WindowsPCToolkit\Suite\Runs`.

Windows 10/11, administrator rights and built-in Windows PowerShell 5.1. General repair is logged maintenance rather than a reversible registry optimization.
