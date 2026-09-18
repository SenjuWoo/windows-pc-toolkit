# PC Cleaner v1.0.2

Scan-first disk cleanup and registry care for Windows 10/11. Built to beat CCleaner (adware), BleachBit (unclear labels, no registry cleaner) and Razer Cortex (bloat) at their own game — while never touching user data.

## The promise

- **Scan first, delete second.** Every run starts with a read-only report: size, file count, risk tag, and one plain-English line explaining what each category is and why it is safe.
- **No forced logouts, ever.** A single guard (`Assert-NotProtected`) blocks deletion of cookies, logins, history, bookmarks, sessions, app storage (IndexedDB/Local Storage), editor history, Extensions, and your Desktop/Documents/Pictures/Videos/Music/OneDrive folders. It runs before *every* deletion, in every code path.
- **Honest counts.** Locked/in-use files are skipped and counted, never force-killed.
- **Registry care with a real undo.** Every registry removal exports a `.reg` backup first; menu option 7 restores the latest batch. Only *provably* orphaned entries are listed.
- **Models are yours.** Local AI model stores (LM Studio, Ollama, Hugging Face, torch, whisper) are shown with sizes so you can decide — this tool will never delete them.

## What it cleans

| Section | Balanced (safe) | Strict (opt-in) |
|---|---|---|
| System | user temp, Windows temp, thumbnails/icons, WER queues, crash dumps, INetCache, Delivery Optimization, CBS/DISM logs | Windows Update download cache, Prefetch, Windows.old |
| Browsers | Edge, Chrome, Opera GX, Firefox caches (page/GPU/system only) | PWA/service-worker caches |
| AI & Dev | Edge/Chrome AI model-store caches, Copilot app caches, VS Code/Cursor/Windsurf caches | Windows Recall snapshots (loud warning) |
| Graphics | NVIDIA/AMD/Intel/D3D shader caches | — |
| Files | `.bak`/`.old`/`.tmp`/`.orig` patcher leftovers **only when the original file still exists** | — |

Registry Care menu: orphaned uninstall entries, dead Run/RunOnce values, stale App Paths, stale MuiCache entries, dead Startup-folder shortcuts.

## What this tool deliberately does NOT do

- No cookie/history/session deletion (that is a browser feature, not a cleaner's).
- No "registry defrag", no CLSID/COM surgery, no "invalid key" cleanup — the classic snake-oil.
- No quarantine folder (caches regenerate; registry has `.reg` backups).
- No service manipulation, no forced file deletion.

## Why not CCleaner / BleachBit / Razer Cortex?

| | CCleaner | BleachBit | Razer Cortex | PC Cleaner |
|---|---|---|---|---|
| Ads / upsell / account | ads + upsell | none | account + overlay | **none** |
| Starts with a scan you can read | manual | preview-first | yes | **yes, every row labeled** |
| Registry cleaner | yes (aggressive, no restore) | **none** | none | **orphan-only, `.reg`-backed, restorable** |
| Cookie-safe by construction | no (opt-out) | opt-in per cleaner | unclear | **hard-coded guard** |
| `.bak`/`.old` leftover rule | no | no | no | **sibling-verified only** |
| AI model-store visibility | no | partial | no | **yes (report + size, never deletes)** |

## Launch

Double-click `Run_As_Admin.bat`, accept UAC, start with **[1] Scan**. If it ever fails to start, the launcher writes the reason to `%LOCALAPPDATA%\Temp\PCCleaner_launch.log` and keeps the window open.

## Files

- `PC_Cleaner.ps1` — the tool (Windows PowerShell 5.1)
- `Run_As_Admin.bat` — elevated launcher
- `validate_syntax.ps1` — parser check
- `PC_Cleaner.ps1 -Action Scan` — non-interactive read-only scan
- `PC_Cleaner.ps1 -Action SelfTest` — asserts the guard and the `.bak` rule

Runtime state: `%ProgramData%\WindowsPCToolkit\Cleaner\` — `Logs`, `RegistryBackups`, `FileBackups`.
