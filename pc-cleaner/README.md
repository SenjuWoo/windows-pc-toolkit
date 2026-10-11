# PC Cleaner 1.1.1

Scan-first cleanup and targeted registry repair. Use the [dashboard](../README.md) or `Run_As_Admin.bat` for the detailed console. Extract the complete toolkit; registry care uses shared root `Modules`.

Elevation preserves the originating Windows account identity. If Windows asks for a different administrator account, the cleaner refuses to act on that account's files or HKCU settings.

| Profile | Categories |
| --- | --- |
| Balanced | Aged user/Windows Temp, thumbnail/icon caches, error-report queues, WinINet/browser page caches, editor caches and official Delivery Optimization cleanup. |
| Strict, selected and confirmed | Shaders, crash dumps, servicing logs, Prefetch and extra browser caches. Recompiling shaders can cause stutter after cleanup. |
| Report only | AI model/app stores, Recall data, patcher backups/leftovers, Windows Update download folders and Windows.old. The category executor cannot delete them. Use Windows storage/servicing tools for update/rollback data. |

Protected names include cookies, logins, history, bookmarks, sessions, app storage, editor history/extensions, personal folders and common local model stores. Cleanup checks links in every parent directory as well as the target, so a browser profile or cache below a junction is kept. Temp scan totals include only files older than seven days for both writing and access; cleanup checks the age again before deletion. Deleted files are not undoable.

All report-only categories appear in the scan. Windows.old, patcher backups, AI stores, Recall data and Windows Update downloads cannot be deleted by any cleaner profile or an older category descriptor. Delivery Optimization reports the measured before/after reduction rather than claiming all cached files were removed; command failures remain failures in the run report.

## Registry care

Missing targets are listed for review. Only dead Run/RunOnce and MuiCache values with executables confirmed absent on a ready fixed local drive are eligible for removal. The startup command is read again immediately before repair. Offline/removable/network targets, ambiguous unquoted paths, permission failures, uninstall/App Paths registrations and shortcuts are kept.

Numbered choices use one consistent order. Each removal saves exact value/type to the Suite journal before writing. A failed write attempts to restore that value. Menu **7** restores the latest registry-care operation, checks the result and preserves intervening changes. Legacy `.reg` backups remain available when no new registry-care journal exists; importing whole legacy keys requires confirmation, and existing shortcut files are preserved.

No broad sweep, COM deletion, registry defrag or FPS claim from unused keys.

```powershell
.\PC_Cleaner.ps1 -Action Scan
.\PC_Cleaner.ps1 -Action SelfTest
.\PC_Cleaner.ps1 -DebugLog
```

Logs: `%ProgramData%\WindowsPCToolkit\Cleaner\Logs`. New registry recovery: `WindowsPCToolkit\Suite\Runs`. Launch errors: `%LOCALAPPDATA%\Temp\PCCleaner_launch.log`.

Debug logging is off by default. `-DebugLog` or `WINDOWS_PC_TOOLKIT_DEBUG=1` records the version, resolved paths, state changes and failures in `%LOCALAPPDATA%\WindowsPCToolkit\Logs\Cleaner_debug.log`, rotating at 1 MiB. Importing the cleaner as a library stays quiet. Run reports use unique names so rapid repeated runs keep their own evidence.

Audit regression checks, from the matching source checkout only: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ..\tests\Test_AuditCleaner.ps1`.
