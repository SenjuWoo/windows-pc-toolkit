# Windows PC Toolkit handoff

## Current milestone

Source is 3.1.0. It is not a published release. Feature commit `e93d5015bca40d434d08233bfb9dbaecf18e1b1e` is on main. [CI](https://github.com/SenjuWoo/windows-pc-toolkit/actions/runs/40039808260) and [CodeQL](https://github.com/SenjuWoo/windows-pc-toolkit/actions/runs/40039807638) completed successfully on that SHA. Open Dependabot, code-scanning and secret-scanning alerts were zero after that push. Code quality is unavailable and stays off. The downloadable ZIP and Latest release remain 3.0.2 until a hashed payload is built from a green SHA. 3.1.0 adds the OneDrive folder page: sign in and choose Only on my PC before uninstall, or Desktop, Documents, Pictures, Music and Videos keep the OneDrive path. The lock writes only `KFMBlockOptIn` dword 1, and only after every known folder is local or a custom path. It does not move or delete files and does not run an uninstaller. A location restore runs only when OneDrive.exe is already gone and a folder still points at OneDrive, and that report is not undone.

Published 3.0.2 remains the last known-good public release. Findings for that audit: docs/AUDIT_2026-10-11.md. Current coverage: VALIDATION_REPORT.md and docs/releases/v3.1.0.md.

Release commit for 3.0.2: `d8d263012bcc55e92c2081e89444f1532cd847d8` (annotated tag `v3.0.2`). [Public release](https://github.com/SenjuWoo/windows-pc-toolkit/releases/tag/v3.0.2). Exact-commit [CI](https://github.com/SenjuWoo/windows-pc-toolkit/actions/runs/38183368793) and [Actions analysis](https://github.com/SenjuWoo/windows-pc-toolkit/actions/runs/38183368698) completed successfully. Analysis covers Actions, not the PowerShell implementation. Dependabot, code-scanning and secret-scanning open alerts were independently queried after that publication: zero in each category. Unavailable code quality remains off. Those alert counts are for the 3.0.2 publication, not for the unpublished 3.1.0 source.

## Verified evidence

- On 2026-10-23, native Windows PowerShell 5.1 STA passed 614 assertions in the 3.1.0 source: OneDrive gate 30, base 117, Suite 48, Cleaner 57, DNS/privacy 99, repair/gaming 49, launchers 125, final gaming 24 and final Fixer 65. `Validate_All.ps1` passed on 46 PowerShell files. The dashboard render is `docs/images/dashboard.png` at 1200 by 860. No live optimize, debloat, DNS change, repair, or OneDrive uninstall was run. The OneDrive tests use `HKCU:\Software\WindowsPCToolkitTests` and a temp profile.
- The 3.0.2 publication evidence stays: 583 assertions in the source, extracted release and installed friendly layout (base 116 plus the same later suites). Hosted administrative CI passed 571 assertions in each layout; 12 fixture-only principal checks are omitted there. Static validation then covered 45 PowerShell files.
- Native read-only DNS capture exposed trailing registry NUL padding. Capture and historical DNS/Fixer recovery now handle only trailing padding; malformed fields and embedded corruption remain refused. Before/after adapter DNS and DoH configuration matched. The existing Suite state root also passed the new ownership/permissions checks.
- The build verified all 86 source files and all 66 payload files against the release commit's Git blobs. The extracted payload passed native/static gates and payload-only read-only CLI preview.
- All three public assets were freshly downloaded and matched local size, SHA-256 and GitHub digest. ZIP: 285924 bytes, SHA-256 `3e6aa7ac39a7f354b72f5e57ae3c7077fb782e9f978da3ab2fe245e6c56d208b`. Attached release-provenance.json identifies the exact commit and CI runs.
- The local upgrade verified and backed up all 75 prior owned files, previous release assets and prior verification manifest before writing. After installed tests, all 79 current owned files and three release assets matched their expected hashes. Independent optimizerDuck and unrelated user-owned files/releases were preserved. Installed verification: `_github_publish/installed-3.0.2-audit-verification.json`, status `VerifiedInstalledAndPublished`, 583 checks. The original source checkout is fast-forwarded separately; its current SHA is recorded in that private manifest.

The 3.0.2 private publish helper `_github_publish` is not in this checkout after the PC reset. Do not invent a 3.1.0 ZIP. Build the payload from the green commit the way 3.0.2 was built, then hash the bytes. The published 3.0.2 ZIP is unchanged.

## Resume contract

- Read this file and git status before writing. Preserve unrelated edits, user data, previous releases/backups and independent optimizerDuck.
- Use native Windows PowerShell 5.1 STA for tests/Test_All.ps1 and run Validate_All.ps1. Mutating Windows commands must remain intercepted or confined to owned HKCU/TEMP fixtures. Never infer live repair success from fixture results.
- Future releases: push first, require successful checks on the exact SHA, query all three GitHub alert categories, build from that clean commit, compare extracted Git blobs, test the package, publish and freshly download/hash-check every asset.
- Before a local upgrade, verify the existing manifest and release assets, back them up and hash-check the backup. Verify the actual installed copy independently.

## Last known good backup

3.0.1 remains available at its [public release](https://github.com/SenjuWoo/windows-pc-toolkit/releases/tag/v3.0.1): commit `f9459671921716a5bfe06a69964b105d2f5ce6ac`, ZIP SHA-256 `79c6565f08efe09cad4d478e505a77533df8ff4979a0a04529f45cd3fdf05bdf`. The local release-3.0.2 upgrade backup contains its 75 owned files and old assets; older pre-audit and 3.0.1 backups remain intact. Keep these for rollback.

## Boundaries and diagnostics

No live optimization, debloat, DNS change, Windows repair, servicing, app removal or FPS certification was performed. Interactive UAC and live repair, AppX/Recall/provider outcomes remain untested. Run one component operation at a time; advanced snapshot restore can replace later manual changes. Unsafe old cleaner file/whole-key imports are retired while their backups remain for manual recovery. Deleted cache/app data is not restored by journals.

Diagnostics: %LOCALAPPDATA%\WindowsPCToolkit\Logs; detailed logging via -DebugLog or WINDOWS_PC_TOOLKIT_DEBUG=1. Reports/recovery journals remain under %ProgramData%\WindowsPCToolkit.
