# Windows PC Toolkit handoff

## Current milestone

Version 3.0.1 correctness audit is [published and verified](https://github.com/SenjuWoo/windows-pc-toolkit/releases/tag/v3.0.1). Release commit: `f9459671921716a5bfe06a69964b105d2f5ce6ac`. [CI](https://github.com/SenjuWoo/windows-pc-toolkit/actions/runs/38099143408) and [GitHub Actions analysis](https://github.com/SenjuWoo/windows-pc-toolkit/actions/runs/38099143671) passed on that exact commit. All three published assets were downloaded through their public URLs and matched local size, SHA-256 and GitHub digests.

The portable archive contains 64 payload files verified against the tagged Git blobs. Its extracted application passed 408 local assertions, static validation and a payload-only CLI preview. Hosted CI passed 396 assertions in each folder layout. The installed friendly-layout copy passed all 408 assertions and static validation; all 75 owned files were hash-verified. Previous application files and release assets were backed up, and the independent optimizerDuck executable was preserved.

ZIP SHA-256: `79c6565f08efe09cad4d478e505a77533df8ff4979a0a04529f45cd3fdf05bdf`. Checksums and commit/CI provenance are attached to the release. Dependabot, code-scanning and secret-scanning alert queries returned zero open alerts. Code quality is unavailable on this repository; Actions CodeQL does not scan PowerShell implementation code.

The whole project was reviewed from public 3.0.0 (`b73f3887b7dbca7453bfea5e77512660dceb4b68`). Implementation findings are in [the audit](docs/AUDIT_2026-10-10.md); verification boundaries and reproduction commands are in [VALIDATION_REPORT.md](VALIDATION_REPORT.md).

## Resume contract

- Read this file and `git status` first; preserve unrelated edits and installed reports/configuration.
- Run `tests/Test_All.ps1` in Windows PowerShell 5.1 STA and `Validate_All.ps1`. Current suites expect 408 assertions on a nonadministrative host, 396 on an administrative CI token.
- CI must pass on the exact release commit in canonical and friendly folder layouts. Query Dependabot, code-scanning and secret-scanning alerts separately.
- Build from that green commit, verify extracted files against Git blobs, test the actual package, then publish and download every asset again to compare size and SHA-256. Keep the previous release and verified local backup.
- Preserve the independent optimizerDuck executable and user-owned files when syncing the installed toolkit.

## Scope and remaining work

The audit and release are complete. The launcher inventory excludes retained source/backup staging and normalizes Windows 8.3 paths; a native short-path reproduction fails before the correction and passes afterward. This task adds no optimization/debloat features or dependencies. Further feature expansion awaits a separate task. This handoff update changes documentation only; the public release remains pinned to the commit above.

No live optimization, debloat, DNS change, servicing, repair or app removal was applied to the development PC. Mutation paths use intercepted commands and disposable fixtures. Interactive UAC, live repair/AppX/Recall/provider outcomes and performance gains remain unproven.

Diagnostics: `%LOCALAPPDATA%\WindowsPCToolkit\Logs`; enable detailed logging with `-DebugLog` or `WINDOWS_PC_TOOLKIT_DEBUG=1`. Reports and recovery journals remain under `%ProgramData%\WindowsPCToolkit`.
