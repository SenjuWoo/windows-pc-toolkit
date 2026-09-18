# PC Cleaner v1.0.0 — design spec (2026-09-18)

## Goal

A fifth toolkit tool that beats CCleaner (adware), BleachBit (unclear labels, no registry cleaner, thin Windows coverage) and Razer Cortex (bloat) at their own game: **scan-first, plainly labeled, honest disk cleanup + registry care** that never touches user data.

## Non-goals

- No "registry defrag", no CLSID/COM surgery, no "invalid key" snake-oil cleaning.
- No cookie/history/session deletion — ever (no forced logouts).
- No quarantine folder (caches regenerate; registry has .reg backups).
- No HTML report (console + JSON log only).
- No service manipulation (WU cache files that are locked are simply skipped).

## Architecture

Single file `pc-cleaner/PC_Cleaner.ps1` + `Run_As_Admin.bat` + `README.md` + `validate_syntax.ps1`. One `$Categories` data table drives a generic scan/clean engine. Registry Care is a section inside the same tool.

## Safety rails

1. **One choke point** — `Assert-NotProtected` runs before every deletion. Protected names (path segments, case-insensitive): Cookies, Login Data, History, Bookmarks, Web Data, Local Storage, IndexedDB, Sessions, Preferences, Extensions, Desktop, Documents, Pictures, Videos, Music, OneDrive, Dropbox, Google Drive, …
2. Scan-first UX: nothing is deleted without an explicit profile/pick + confirmation.
3. Locked/in-use files are skipped and counted (honest tallies).
4. Recycle Bin is never in a profile — explicit menu item only.
5. Registry removals always export `.reg` backups first; one-key restore menu item; manifest JSON per run.
6. `.bak/.old/.tmp/.orig` files are deleted **only** when a sibling original exists; orphans are kept and reported.
7. AI model stores (LM Studio, Ollama, HF, torch, whisper) are report-only: size shown, never deleted.

## Categories

Balanced (safe): user temp, Windows temp, thumbnails/icon cache, WER queues, crash dumps/minidumps, INetCache, Delivery Optimization, CBS/DISM logs, Edge/Chrome/Opera GX/Firefox caches, GPU shader caches, VS Code/Cursor/Windsurf caches, AI assistant model caches, sibling-verified `.bak` leftovers.

Strict (opt-in): Windows Update download cache, Prefetch, PWA/service-worker caches, Windows Recall snapshots, Windows.old removal.

Report-only: AI model stores.

Registry Care: orphaned uninstall entries, dead Run/RunOnce values, stale App Paths, stale MuiCache entries, dead Startup-folder shortcuts.

## UX

Menu: Scan / Balanced / Strict / pick categories / Registry Care / Empty Recycle Bin / Restore registry backup / Exit. Every scan row shows: risk tag, size, file count, plain-English description.

## Verification

- `-SelfTest`: asserts the protected-path guard (blocks `Cookies`, allows `Cache`) and the sibling-`.bak` rule on temp fixtures.
- `-Action Scan`: read-only, CI-safe.
- `Validate_All.ps1`: new checks — cleaner present, guard + backup markers present, and delete-call patterns for protected names are forbidden.

## Release

Toolkit v2.1.0, PC Cleaner v1.0.0. New zip `pc-cleaner-v1.0.0.zip`; full package `windows-pc-toolkit-v2.1.0.zip`; README/CHANGELOG/VALIDATION_REPORT/START_TOOLKIT updated.
