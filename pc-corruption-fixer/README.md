# PC Corruption Fixer v7.1.1

A Windows 10/11 repair and diagnostic toolkit built around official Windows tools, detailed logs, and conservative defaults.

## Major v7.1 / 7.1.1 fixes

### Hotfix 7.1.1

- Fixed a PowerShell parser failure from an unbraced variable followed by a colon in a catch message (${name}:).


### Disk scan failure fixed

The old Full Repair attempted `chkdsk.exe /scan` first. On some elevated systems, PowerShell rejected that native pipeline with **Access is denied** before CHKDSK completed. The script then used `Repair-Volume`, but the timer had already stopped, which produced a misleading `0.0s` result.

v7.1 now:

1. Uses `Repair-Volume -Scan` as the primary online disk scan.
2. Falls back to `chkdsk /scan` only if the cmdlet cannot run.
3. Keeps the stopwatch running through every fallback.
4. Uses the actual Windows drive instead of hard-coding `C:`.
5. Recommends `Repair-Volume -OfflineScanAndFix` when an offline repair is required.

### Full Repair is no longer a network reset

Routine corruption repair should not reset Winsock, TCP/IP, firewall rules, DNS, or DoH. Full Repair now performs a non-destructive DNS refresh and connectivity check instead. The explicit **Network Stack Reset** remains available as menu option 4 for real network-stack failures.

Before that explicit reset, v7.1 saves whether DNS was automatic or static, the static DNS addresses, and registered DNS-over-HTTPS templates under:

`%ProgramData%\WindowsPCToolkit\PCFixer\NetworkSnapshots`

Winsock reset is the default repair. The deeper TCP/IP reset is separately confirmed because it can remove custom static IP, gateway, VLAN, VPN, and adapter settings. After either path, the tool restores the recorded DNS mode and DoH templates, and it reports a failure instead of pretending rollback succeeded.

### Reversible AI feature privacy

Menu option 23 no longer removes Copilot/AI AppX packages, disables services, or turns off Windows Search. It applies a documented policy-only profile for Recall, Click to Do, Settings agentic search, Edge AI features, and local Edge/Chrome GenAI models. Before changing anything, it saves the exact registry state under:

`%ProgramData%\WindowsPCToolkit\PCFixer\AIFeatureSnapshots`

The same menu can restore the latest snapshot. A failed apply automatically rolls back. Windows may ignore particular enterprise policies on unsupported editions or older builds, so the tool reports policy application rather than pretending every AI component was uninstalled.

### Other safety corrections

- Recycle Bin deletion is separately opt-in and never part of Full Repair.
- A stopped Windows Update service is reported as healthy when it is Manual/trigger-start, which is normal on current Windows versions.
- Windows Update repair refreshes DNS but no longer resets Winsock.
- Full Repair preserves firewall rules, adapter settings, DNS, DoH, static IP settings, and DHCP leases.

## Full Repair sequence

1. SFC system file scan
2. Conditional DISM component-store repair
3. Safe cache cleanup
4. DNS refresh and network health test
5. Online disk health scan

## Menu tools

- SFC and DISM repair
- Safe temporary/cache cleanup
- Explicit Winsock reset, with deeper TCP/IP reset separately confirmed and DNS/DoH rollback checked
- DISM component cleanup, with irreversible ResetBase separately confirmed
- Online disk health scan
- Windows Update health check and repair
- Microsoft Store/AppX repair
- Critical service checks
- Event log scan
- Network diagnostics
- Problem device scan
- Disk space analysis
- Startup viewer
- Icon/thumbnail cache rebuild
- Time synchronization repair
- Performance counter repair
- Orphaned service scan
- Reversible AI feature privacy policy manager
- HTML health report

## Launch

Double-click `Fix_Corruption.bat`, accept UAC, and select a menu option. Logs are written to the Desktop.

## Safety notes

- Native Windows executables are resolved from the trusted System32 directory.
- Windows Update data is not deleted by cache cleanup.
- TCP/IP reset, firewall reset, and DISM ResetBase are explicit opt-ins.
- Network reset is not part of Full Repair.
- A restore point is offered before Full Repair.
- Read-only diagnostic items are labeled as such.

## Requirements

- Windows 10 or Windows 11
- Administrator rights
- Built-in Windows PowerShell 5.1 or newer
