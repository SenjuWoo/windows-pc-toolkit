# Windows PC Toolkit handoff

## Current milestone

3.0.2 final safety cross-audit is integrated, not yet released. Baseline: clean main `5a3fb95e08678ea03b2cd7e73e147415ad560d30`; last public release 3.0.1 at `f9459671921716a5bfe06a69964b105d2f5ce6ac`. Preserve the current git diff. Findings are in docs/AUDIT_2026-10-11.md; no feature expansion or dependencies were added.

The final integrated native gate passed 583 assertions on this nonadministrative host: base 116, Suite 48, Cleaner 57, DNS/privacy 99, repair/gaming 49, launchers 125, final gaming 24, final Fixer 65. Administrative CI tokens omit 12 fixture-only principal-gate checks and report 571. Static validation passes on 45 PowerShell files. Actual WPF 3.0.2 screenshot rendered and visually inspected. VALIDATION_REPORT.md records the final counts and coverage.

Read-only native DNS capture found trailing NUL padding in registry NameServer values. Shared capture now trims terminator padding; the native schema-4 capture passes with configuration unchanged. DNS/Fixer restore normalizes that same historical padding, rejects embedded corruption, and passes focused fixtures. All component edits are frozen. Private evidence and Build-Release.ps1 / Verify-Published.ps1 / Sync-Release.ps1 helpers are in the adjacent Toolkit-final-audit-2026-10-11 folder.

Remaining gates: commit/push, exact-SHA green CI plus all three GitHub alert queries, extracted payload/Git-blob/native checks, tag/release/public downloads, verified backup + local friendly-layout sync, installed native/static/hash checks, final handoff. Private release helpers take ExpectedChecks=583. No live optimization, debloat, DNS change, repair, servicing or app removal has been applied.

## Resume contract

- Read this file and git status before writing; preserve unrelated edits, user data, previous releases and independent optimizerDuck.
- Use native Windows PowerShell 5.1 STA for tests/Test_All.ps1; run Validate_All.ps1. Mutating Windows commands must remain intercepted or confined to owned HKCU/TEMP fixtures.
- Push first; exact release SHA must pass canonical/friendly CI and analysis. Query Dependabot, code-scanning and secret-scanning alerts independently. Actions analysis does not scan PowerShell implementation code; unavailable code quality stays off.
- Build from the green clean commit, compare all extracted files to Git blobs, run actual package tests and payload-only preview, publish and freshly download every asset to compare size/SHA-256/GitHub digest.
- Before local sync, verify all old manifest files and old public assets; back them up and hash-check the backup. Preserve user-owned files, prior backups and optimizerDuck. Verify the installed copy independently.

## Last known good release

[3.0.1 public release](https://github.com/SenjuWoo/windows-pc-toolkit/releases/tag/v3.0.1): commit f9459671921716a5bfe06a69964b105d2f5ce6ac, ZIP SHA-256 79C6565F08EFE09CAD4D478E505A77533DF8FF4979A0A04529F45CD3FDF05BDF. Source handoff/main is 5a3fb95e08678ea03b2cd7e73e147415ad560d30. Its three assets were publicly downloaded/hash-verified, and the installed manifest records 75 owned files with 408 native checks. The original source checkout and independent companion were verified unchanged at this audit's start. Keep 3.0.1 and its backups.

## Boundaries and diagnostics

No live Windows mutation or FPS certification. Interactive UAC and live repair, AppX/Recall/provider outcomes remain untested. Run one component operation at a time; advanced snapshot restore can replace later manual changes. Unsafe old cleaner file/whole-key imports are retired while their backups remain for manual recovery. Deleted cache/app data is not restored by the journals.

Diagnostics: %LOCALAPPDATA%\WindowsPCToolkit\Logs; detailed logging via -DebugLog or WINDOWS_PC_TOOLKIT_DEBUG=1. Reports/recovery journals remain under %ProgramData%\WindowsPCToolkit.
