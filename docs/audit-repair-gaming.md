# Repair and gaming audit

Reviewed on 2026-10-10: all files in `pc-corruption-fixer` and `pc-gaming-optimizer`, including the full repair console, shared gaming module, numbered wrappers and batch launchers. This audit adds bug fixes, not new debloat features.

## Corrected defects

- Repair summary called `ContainsKey` on an `OrderedDictionary`, causing an exception at exit. Summary now uses actual results without that invalid method and does not turn warnings/skips into unconditional success.
- Quick Health Scan guessed SFC integrity from numeric exit codes, used English DISM output as a portable verdict, and flagged an idle Manual Windows Update service as broken. It now displays native integrity verdicts, distinguishes command failures and accepts demand-start idle services.
- SFC/component cleanup could run during a pending servicing restart, and SFC continued after DISM failure/restart. Those paths now defer servicing. DISM repair/cleanup explicitly uses `/NoRestart`; deep cleanup releases stay-awake in `finally` and retains a failed ResetBase result.
- DNS flush and performance-counter WMI resync could fail while reporting success. Native exit codes now affect their results, and failure of a requested TCP/IP/firewall reset remains a warning after DNS recovery. Cache cleanup no longer references deleted temp counters, and thumbnail counts reflect successful removals.
- Store repair enumerated every user's AppX packages, then registered them into the current account. Registration now uses only the current user's packages and errors when enumeration fails.
- An unavailable event log could appear clean. The scan and HTML report now share checked event reading; failures remain unavailable/warnings instead of zero-error verdicts. Disabled/unreadable services remain warnings in the service-health summary.
- A failed network time resync automatically unregistered W32Time, losing existing time-source configuration. Failed resync now reports the native cause and preserves configuration.
- Icon rebuild stopped Explorer across all sessions. It now stops/restarts Explorer only in the launching session. Windows-drive diagnostics use `SystemDrive` rather than assuming `C:`.
- Service cleanup treated unreadable/offline/remote paths as missing programs. It now requires a stopped service, a confirmed missing executable on a ready local fixed disk, a fresh state/path check and a nonempty registration backup before deletion.
- AI-policy restore could reject signed DWORD/QWORD values or mishandle singleton Binary/MultiString values; case-insensitive JSON equality could hide an incorrect restoration. Types now round-trip exactly, and snapshot destinations/types are validated before writes.
- Gaming snapshots read and later overwrote unrelated boot/network/service/power state even for a HAGS or mouse change. Schema 3 records originating identity and limits capture to action scope. UTF-8 pointers preserve Unicode paths. Registry targets/types and service/boot/power states are validated before restore; actual typed values, service state/start mode, NIC settings and native outcomes are checked.
- Gaming restore/legacy cleanup suppressed native, registry and service failures while claiming exact success. Failures now propagate. BCD query failure cannot become an all-absent snapshot, and cleanup deletes only present overrides with read-back checks.
- Console SSD ReTrim also targeted HDD/unknown volumes. It now requires a unique SSD serial-number match and supported fixed volumes.
- Shader cleanup followed a linked cache root and could delete unrelated target files. Roots/ancestors and nested entries are checked for reparse points, and linked items are skipped.
- Three batch launchers embedded paths in apostrophe-sensitive PowerShell source, used the Server service as an administrator test, and gaming launchers relied on a timed elevation flag. Paths now cross through environment variables, administrator status uses WindowsPrincipal, and elevation waits for the actual child exit code. Elevation passes the originating user SID; the repair/gaming/VR entry points reject alternate-account elevation before bootstrap and per-user changes.
- Both consoles now provide bounded versioned JSONL diagnostics in LocalAppData. Default logs contain warning/error causes; `-DebugLog` / `WINDOWS_PC_TOOLKIT_DEBUG=1` adds startup/configuration/state detail. Fixer transcripts are optional and retained separately from recovery backups.

## Verification

Run with built-in Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test_AuditRepairGaming.ps1
```

The regression suite passes **49 checks**. It uses real temporary HKCU registry values, JSON serialization, Unicode/apostrophe paths, ordinary cache files, a real directory junction, generated HTML, actual isolated user-identity guards, and a harmless compiled executable to verify Win32 argument quoting and failed native BCD-query handling. Service, storage, AppX, time, event-log and servicing mutations are injected fixtures; no repair or gaming setting is applied to the test host. Existing project integration tests are separate.

## Limits

These checks establish the repaired control flow, state boundaries and native argument handling. They do not certify repair of a corrupt Windows installation, a successful Windows Update, hardware-specific HAGS/VR behavior, AppX re-registration on every build, or FPS improvement. Old gaming snapshots lack computer/user metadata and require explicit review; console restore can replace later manual edits. Use dashboard journals for conflict-aware recovery. ResetBase, deleted shader data and external Windows servicing effects are not reversible by a registry snapshot.

Primary contracts checked: [Add-AppxPackage user scope](https://learn.microsoft.com/powershell/module/appx/add-appxpackage), [SetThreadExecutionState result/flags](https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate), and the actual Windows PowerShell 5.1 parser/runtime and installed native tool interfaces.
