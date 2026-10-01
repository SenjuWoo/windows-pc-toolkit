# Validation report

Windows PC Toolkit 3.0.0, local Windows 11 validation on October 1, 2026.

## Observed results

- **72 regression and real-boundary checks passed** in Windows PowerShell 5.1, STA.
- **37 PowerShell files parsed**, and launcher/DoH/safety checks passed in `Validate_All.ps1`.
- Native WPF loaded **55 controls and 17 optimization choices** from a freshly copied package in a path containing spaces, an apostrophe and non-English text.
- Actual WPF Preview button → Start-Job worker → DispatcherTimer → result text/control refresh completed.
- `docs/images/dashboard.png` rendered from the real WPF tree and visually inspected.
- Read-only native Windows probes loaded OS/hardware, essential services, startup/task and optional-AppX inventories. A redirected DNS snapshot captured schema 4 state without changing adapter configuration.

## Tested boundaries

Real disposable HKCU values and serialized journals cover String, ExpandString, Binary, MultiString, QWord, absent values and UTF-8 text. Exact undo, failed backup before mutation, intervening-user conflicts, repeated undo, interrupted pending writes, combined startup/profile journals and rollback after a partial registry action are exercised.

Real disposable filesystem tests cover old/recent/accessed files, protected data, junction escape prevention, actual deletion and successful-removal accounting. A fresh worker process verifies quoted paths and JSON results; native subprocess tests cover stderr and nonzero exit codes.

Network tests inspect real Windows cmdlet parameter contracts, then replace mutation commands with fakes. They exercise mixed per-family automatic/static modes, updating existing DoH entries, a failed Quad9 live transport test, legacy schema without a computer field, empty encryption arrays, changed interface index with preserved GUID, and missing-adapter preflight failure. They do not apply DNS to the host.

Update-repair fault injection covers failed service stop, partial cache rename, failed service restart and success; no host update folder/service is changed. Interrupted game-session injection verifies priority restoration. Cleaner category checks retain models, backups, Recall and update data as report-only.

## CI and reproduction

The CI workflow runs parser/PSScriptAnalyzer gates, static toolkit validation, this native Windows regression suite, and JSON/Python validation on each pushed commit. Use the [CI run for the exact commit](https://github.com/SenjuWoo/windows-pc-toolkit/actions/workflows/ci.yml), not an older green run, as hosted evidence.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Validate_All.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test_Toolkit.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Toolkit.ps1 -RenderPreview .\docs\images\dashboard.png
```

## Runtime limits

No live optimization profile, adapter DNS change, Windows repair, app removal/re-registration, ReTrim or update-cache rebuild was applied during development. Package backup/re-registration and real provider connectivity need target-machine use to establish their runtime outcome. Saved policy read-back does not establish edition support or FPS gains. Deleted temp/cache files and removed app data are not restored by the journal. No claim of universal compatibility or measured gaming improvement is made.
