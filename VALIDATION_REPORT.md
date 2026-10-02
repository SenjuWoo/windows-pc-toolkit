# Validation report

Windows PC Toolkit 3.0.0, local Windows 11 validation on October 1, 2026.

## Observed results

- **114 regression and real-boundary checks passed** in Windows PowerShell 5.1, STA.
- **37 PowerShell files parsed**, and launcher/DoH/safety checks passed in `Validate_All.ps1`.
- Native WPF loaded **55 controls and 19 optimization choices** from a freshly copied package in a path containing spaces, an apostrophe and non-English text.
- Actual WPF Preview button → Start-Job worker → DispatcherTimer → result text/control refresh completed.
- Actual repair button/worker/timer completed native-process success, failure and restart-required scenarios; a disposable console executable replaced DISM/SFC. The real Windows stay-awake API enabled and released its system-required flag.
- Actual read-only SFC help/error output decoded as UTF-16LE without embedded NUL characters; the disposable SFC fixture emits the same BOM-less encoding.
- Startup, app, adapter, history and health refresh buttons completed against native read-only Windows inventories.
- `docs/images/dashboard.png` rendered from the real WPF tree and visually inspected.
- Read-only native Windows probes loaded OS/hardware, essential services, startup/task and optional-AppX inventories. A redirected DNS snapshot captured schema 4 state without changing adapter configuration.

## Tested boundaries

Real disposable HKCU values and serialized journals cover String, ExpandString, Binary, MultiString, QWord, absent values and UTF-8 text. Exact undo, failed backup before mutation, intervening-user conflicts, repeated undo, interrupted pending writes, combined startup/profile journals and rollback after a partial registry action are exercised.

Actual robocopy and SHA-256 checks run on disposable package files, followed by simulated AppX removal/re-registration and Recall feature APIs. Tests cover protected packages, failed backups blocking removal, default debloat preview, feature-state journaling/undo and already-disabled features. Privacy/AI recovery injection covers denied reads/writes and failed service restart without claiming successful restore.

Real disposable filesystem tests cover old/recent/accessed files, protected data, junction escape prevention, actual deletion and successful-removal accounting. A fresh worker process verifies quoted paths and JSON results; native subprocess tests cover stderr and nonzero exit codes.

Network tests inspect real Windows cmdlet parameter contracts, then replace mutation commands with fakes. They exercise mixed per-family automatic/static modes, updating existing DoH entries, a failed Quad9 live transport test, legacy schema without a computer field, empty encryption arrays, changed interface index with preserved GUID, and missing-adapter preflight failure. They do not apply DNS to the host.

Update-repair fault injection covers failed service stop, partial cache rename, failed service restart and success; no host update folder/service is changed. Interrupted game-session injection verifies priority restoration. Cleaner category checks retain models, backups, Recall and update data as report-only.

Repair tests run the actual orchestration and native process runner with disposable executable output/exit codes. They verify DISM-before-SFC ordering, stopping after a failed command, saved output/report display, restart-required reporting, restored button availability and operation-mutex cleanup. Real P/Invoke checks prevent recurrence of the high-bit hexadecimal-to-UInt32 conversion failure. DNS tests assert that the mutation command resolves to an in-memory function before adapter-family and restore tests.

## CI and reproduction

The CI workflow runs parser/PSScriptAnalyzer gates, static toolkit validation, this native Windows regression suite in both canonical and installed friendly folder layouts, and JSON/Python validation on each pushed commit. Use the [CI run for the exact commit](https://github.com/SenjuWoo/windows-pc-toolkit/actions/workflows/ci.yml), not an older green run, as hosted evidence.

Published releases attach `release-provenance.json` with their exact commit, CI links, archive size and SHA-256. Packaging checks compare every extracted file with that commit's Git blob. Uploaded assets are downloaded again and compared byte-for-byte by SHA-256.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Validate_All.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test_Toolkit.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Toolkit.ps1 -RenderPreview .\docs\images\dashboard.png
```

## Runtime limits

No live optimization profile, adapter DNS change, Windows repair, app removal/re-registration, ReTrim or update-cache rebuild was applied during development. Real AppX uninstall/re-registration, Recall servicing and provider connectivity need target-machine use to establish their runtime outcome. Package-file copy/hash verification used real disposable files; AppX and optional-feature changes were simulated. Saved policy read-back does not establish edition support or FPS gains. Deleted temp/cache files and removed app data, Recall snapshots and browser-built-in AI models are not restored by the journal. No claim of universal compatibility or measured gaming improvement is made.
