# Windows PC Toolkit handoff

## Current milestone

Version 3.0.1 correctness audit implemented. Release preparation is in progress; do not infer publication from README download links. Check the exact tag, CI checks and release assets before claiming it shipped.

The whole project was reviewed from public 3.0.0 (`b73f3887b7dbca7453bfea5e77512660dceb4b68`). Implementation findings are in [the audit](docs/AUDIT_2026-10-10.md); verification boundaries and reproduction commands are in [VALIDATION_REPORT.md](VALIDATION_REPORT.md).

## Resume contract

- Read this file and `git status` first; preserve unrelated edits and installed reports/configuration.
- Run `tests/Test_All.ps1` in Windows PowerShell 5.1 STA and `Validate_All.ps1`. Current suites expect 408 assertions on a nonadministrative host, 396 on an administrative CI token.
- CI must pass on the exact release commit in canonical and friendly folder layouts. Query Dependabot, code-scanning and secret-scanning alerts separately.
- Build from that green commit, verify extracted files against Git blobs, test the actual package, then publish and download every asset again to compare size and SHA-256. Keep the previous release and verified local backup.
- Preserve the independent optimizerDuck executable and user-owned files when syncing the installed toolkit.

## Scope and remaining work

Finish the launcher-inventory test correction for installed source/backup staging and Windows 8.3 paths, then converge CI, package, publish and verify 3.0.1. This task adds no optimization/debloat features or dependencies. Further feature expansion awaits a separate task.

No live optimization, debloat, DNS change, servicing, repair or app removal was applied to the development PC. Mutation paths use intercepted commands and disposable fixtures. Interactive UAC, live repair/AppX/Recall/provider outcomes and performance gains remain unproven.

Diagnostics: `%LOCALAPPDATA%\WindowsPCToolkit\Logs`; enable detailed logging with `-DebugLog` or `WINDOWS_PC_TOOLKIT_DEBUG=1`. Reports and recovery journals remain under `%ProgramData%\WindowsPCToolkit`.
