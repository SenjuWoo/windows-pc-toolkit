# PC Cleaner 1.4.1

Scan-first cleanup and targeted registry repair. Use the [dashboard](../README.md) or `Run_As_Admin.bat` for the detailed console. Extract the complete toolkit; registry care uses shared root `Modules`.

Elevation preserves the originating Windows account identity. If Windows asks for a different administrator account, the cleaner refuses to act on that account's files or HKCU settings.

| Profile | Categories |
| --- | --- |
| Balanced | Aged user/Windows Temp, thumbnail/icon caches, error-report queues, WinINet/browser page caches, editor caches and official Delivery Optimization cleanup. |
| Strict, selected and confirmed | Shaders, crash dumps, servicing logs, Prefetch and extra browser caches. Recompiling shaders can cause stutter after cleanup. |
| Report only | AI model/app stores, AI assistant homes (Codex, Claude, Hermes), Unity project libraries, Recall data, patcher backups/leftovers, Windows Update download folders and Windows.old. The category executor cannot delete them. Use Windows storage/servicing tools for update/rollback data. |

Protected names include cookies, logins, history, bookmarks, sessions, app storage, editor history/extensions, personal folders and common local model stores. Cleanup checks links in every parent directory as well as the target, so a browser profile or cache below a junction is kept. Temp scan totals include only files older than seven days for both writing and access; cleanup checks the age again before deletion. Deleted files are not undoable.

All report-only categories appear in the scan. Windows.old, patcher backups, AI stores, Recall data and Windows Update downloads cannot be deleted by any cleaner profile or an older category descriptor. Delivery Optimization reports the measured before/after reduction rather than claiming all cached files were removed; command failures remain failures in the run report.

## Cache Explorer (v1.4.1)

Menu `[8]` in the console opens a read-only scan of caches that are usually safe to drop, grouped by **AI**, **Gaming** and **Dev**. Nothing runs because a tool is installed: a category appears only when its folder exists, and deletion always asks first.

| Section | Category | Default | What it touches |
| --- | --- | --- | --- |
| AI | Antigravity editor caches | SAFE | `Cache`, `Code Cache`, `CachedData`, `GPUCache` under `%APPDATA%\Antigravity`, and only when the sibling `User` folder proves the layout |
| AI | Codex catalog cache | REPORT | `cache\codex_app_directory`, `codex_apps_server_info`, `codex_apps_tools`, `remote_plugin_catalog`. Regenerable, but the `.codex` home is protected wholesale: sessions, SQLite state, config and secrets share the tree |
| AI | Claude Code shell snapshots | REPORT | `snapshots`-style `snapshot-bash-*.sh` shell state. Regenerable, but it lives under the protected `.claude` home |
| AI | Codex / Claude / Hermes home | REPORT | Measured, never deleted. Sessions, SQLite state, `.claude.json`, memories, skills, `tmp\arg0` and `state.db` are outside the cleaner's authority |
| Gaming | Steam shader cache | STRICT | `steamapps\shadercache` in every library found through `libraryfolders.vdf`, including the default `Program Files (x86)` install. The exact folder Steam reports is the only Program Files path the cleaner may touch; `common`, `compatdata`, installers and manifests are never included |
| Gaming | Steam staging temp | REPORT | `steamapps\temp` can hold an unfinished update, so it is measured and never removed |
| Gaming | VRChat cache | CAREFUL | the `config.json` `cache_directory` when it passes the cleanup-root validator, else `LocalLow\VRChat\VRChat\Cache-WindowsPlayer`; `config.json`, screenshots and moderation data stay. The location is re-read before deletion and a config that moved, vanished or stopped parsing refuses the row instead of falling back |
| Gaming | Epic Launcher web cache | REPORT | `Saved\webcache*`; the browser `WebCache` guard covers this name, so clear it from the launcher |
| Gaming | Roblox / Minecraft logs | SAFE | `*.log*` older than seven days; autosaves, saves, mods and packs stay |
| Dev | pip / npm / NuGet HTTP caches | SAFE | Download caches only; the NuGet global packages folder is not included |
| Dev | Unreal DerivedDataCache, Gradle caches | STRICT | Rebuild cost is printed before the confirmation; the editor or JVM must be closed |
| Dev | Yarn cache | SAFE | `Yarn\Cache`, `Yarn\Berry\cache`; packages download again |
| Dev | pnpm store | REPORT | Hard-linked into every project; `pnpm store prune` is the right tool |
| Gaming | GPU driver + DirectX shader caches | STRICT | `NVIDIA\DXCache`, `NVIDIA\GLCache`, `AMD\DxCache`, `D3DSCache`; opt in, recompiles cause first-launch stutter |
| Dev | Unity project `Library` | REPORT | Not enumerated: project paths cannot be discovered safely |

### What each risk level means

| Level | Confirmation | What happens |
| --- | --- | --- |
| SAFE | One `y` | Download caches and logs the owning application recreates; nothing user-authored is in scope |
| CAREFUL | One `y` plus the category id | Data the application rebuilds at a cost (VRChat re-downloads avatars); configuration and user files stay |
| STRICT | The category id typed back | Data whose loss is visible: shader and pipeline caches recompile on next launch, Unreal and Gradle rebuild from source |
| REPORT | None, deletion refused | Measured and explained only. Used where a folder is disposable by name but its parent tree holds credentials, sessions or user data, or where the deletion guard would refuse the path anyway |

A row is shown as cleanable only when the scan and the deletion guard agree: the same `Test-CleanupRoot` policy that measures a category is the one that runs at delete time. Steam's shader cache is the single exception to the Program Files rule, and it is granted by an exact match against the libraries Steam reports live, not by a folder name.

Every row carries its source and rebuild impact. **Clean SAFE caches** only offers SAFE rows whose layout is verified and whose app is closed; STRICT and CAREFUL rows need the category id typed back. **Export JSON report** writes the measurement, not a promise of reclaimed space.

The scan is bounded (50,000 files per category) so a large library cannot freeze the console. Sizes are estimates; each cleanup reports the bytes it actually removed, plus skipped files.

## Skyrim & Modding Cleanup (menu `[9]`)

Resolves the Windows Documents known folder and searches only `My Games\Skyrim Special Edition` and `My Games\Skyrim VR`:

| Source | Files | Level |
| --- | --- | --- |
| `SKSE` | `.log` / `.logN` from SKSE and plugins | SAFE (older than 7 days) or HARD (any age) |
| `Logs\Script` | `Papyrus*.log` rotations | SAFE or HARD |
| MO2 `logs` | `mo_interface*.log`, `usvfs-*.log` | SAFE or HARD |
| Vortex | `vortex*.log` | SAFE or HARD |
| DynDOLOD `Logs` | `DynDOLOD_*_log.txt`, `TexGen_*_log.txt`, `LODGen_*_log.txt` | SAFE or HARD |

A portable MO2 or DynDOLOD install is listed only when its folder is passed in (menu `[5]`); no drive is searched. Mods, profiles, overwrite, downloads, Vortex state and generated LOD output are never eligible.

Only those extensions are eligible. Saves, `.ini`, `.json`, `.toml`, `.yaml`, `.dll`, `.pex`, `.psc`, archives and unknown types stay. This is the one approved bypass of the `Documents` guard: the file must be a direct child of an approved game-log folder, match the log pattern, be regular and have no reparse point in any parent — rechecked immediately before deletion. Cloud-synced Documents folders and Mod Organizer 2 / Vortex data folders are report-only.

## Guards

The existing choke point still decides every deletion: protected names, reparse points in any parent, reparse points or protected names inside a directory, and locked files all skip. The explorer adds four gates on top:

1. `Delete = false` categories are measured and refused, never removed.
2. A `Signature` folder must exist, so a lookalike directory is not treated as the app's cache.
3. A running application blocks its own category.
4. A cache root holding a protected folder is refused whole instead of being half-emptied.

`AgeDays` is checked per item immediately before removal. Cache deletion is irreversible and may require a rebuild or a re-download; no automatic recovery is offered, and a quarantined folder on the same drive would not reclaim space anyway.

## Registry care

Missing targets are listed for review. Only dead Run/RunOnce and MuiCache values with executables confirmed absent on a ready fixed local drive are eligible for removal. The startup command is read again immediately before repair. Offline/removable/network targets, ambiguous unquoted paths, permission failures, uninstall/App Paths registrations and shortcuts are kept.

Numbered choices use one consistent order. Each removal saves exact value/type to the Suite journal before writing. A failed write attempts to restore that value. Menu **7** restores the latest registry-care operation, checks the result and preserves intervening changes. Old file-copy/whole-key `.reg` manifests are kept for manual recovery; automatic legacy import is retired because those manifests cannot establish safe targets or original identity. The console displays their folder without copying files or importing keys.

No broad sweep, COM deletion, registry defrag or FPS claim from unused keys.

```powershell
.\PC_Cleaner.ps1 -Action Scan
.\PC_Cleaner.ps1 -Action SelfTest
.\PC_Cleaner.ps1 -DebugLog
```

Logs: `%ProgramData%\WindowsPCToolkit\Cleaner\Logs`. New registry recovery: `WindowsPCToolkit\Suite\Runs`. Launch errors: `%LOCALAPPDATA%\Temp\PCCleaner_launch.log`.

Debug logging is off by default. `-DebugLog` or `WINDOWS_PC_TOOLKIT_DEBUG=1` records the version, resolved paths, state changes and failures in `%LOCALAPPDATA%\WindowsPCToolkit\Logs\Cleaner_debug.log`, rotating at 1 MiB. Importing the cleaner as a library stays quiet. Run reports use unique names so rapid repeated runs keep their own evidence.

Audit regression checks, from the matching source checkout only: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ..\tests\Test_AuditCleaner.ps1`.
