# PC Cleaner 1.1

Scan-first cleanup and targeted registry repair. Use the [dashboard](../README.md) or `Run_As_Admin.bat` for the detailed console. Extract the complete toolkit; registry care uses shared root `Modules`.

| Profile | Categories |
| --- | --- |
| Balanced | Aged user/Windows Temp, thumbnail/icon caches, error-report queues, WinINet/browser page caches, editor caches and official Delivery Optimization cleanup. |
| Strict, selected and confirmed | Shaders, crash dumps, servicing logs, Prefetch and extra browser caches. Recompiling shaders can cause stutter after cleanup. |
| Report only | AI model/app stores, Recall data, patcher backups/leftovers, Windows Update download folders and Windows.old. The category executor cannot delete them. Use Windows storage/servicing tools for update/rollback data. |

Protected names include cookies, logins, history, bookmarks, sessions, app storage, editor history/extensions and personal folders. Temp cleanup keeps recent/recently accessed files, skips links and does not kill apps. Counts reflect successful removal; deleted files are not undoable.

## Registry care

Missing targets are listed for review. Only dead Run/RunOnce and MuiCache values with executables confirmed absent on a ready fixed local drive are eligible for removal. Offline/removable/network targets, permission failures, uninstall/App Paths registrations and shortcuts are kept.

Numbered choices use one consistent order. Each removal saves exact value/type to the Suite journal before writing. Menu **7** restores the latest registry-care operation, checks the result and preserves intervening changes. Legacy `.reg` backups remain available when no new registry-care journal exists.

No broad sweep, COM deletion, registry defrag or FPS claim from unused keys.

```powershell
.\PC_Cleaner.ps1 -Action Scan
.\PC_Cleaner.ps1 -Action SelfTest
```

Logs: `%ProgramData%\WindowsPCToolkit\Cleaner\Logs`. New registry recovery: `WindowsPCToolkit\Suite\Runs`. Launch errors: `%LOCALAPPDATA%\Temp\PCCleaner_launch.log`.
