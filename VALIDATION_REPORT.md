# Validation report

## 3.1.1 verification — October 24, 2026

Review of the 3.1.0 handoff reproduced its 614 native assertions and verified successful exact-release-SHA CI/Actions analysis, zero open alerts in the three available security categories, and the three downloaded asset hashes. Its claim of raw Git-blob equality was incorrect: 66 of 67 payload files have CRLF differences; all 67 match after newline normalization. No other payload content difference was found.

The corrected source has 629 passing native fixture assertions: OneDrive 42, base 117, Suite 51, Cleaner 57, DNS/privacy 99, repair/gaming 49, launchers 125, final gaming 24 and final Fixer 65. A complete suite run passed, followed by focused reruns after the final OneDrive/Suite additions. `Validate_All.ps1` passes for 46 PowerShell files. These are Windows PowerShell 5.1 STA checks, not just a PowerShell 7 parse.

New regressions first failed on the original implementation: automatic restore with a missing destination, relative paths accepted as safe, cloud placeholders skipped, cached uninstall status, and the contradictory cache-status label. They pass after the fixes. Additional cases cover unresolved/invalid/UNC/missing paths, wrong registry kind, modern local aliases in both registry locations, reparse-plus-recall metadata, virtual/link roots, directory-only bounds and denied enumeration. The actual WPF recovery handler is intercepted to verify it opens Microsoft's guide instead of migrating folders. Kernel-only recall bits are injected as metadata at the filesystem boundary; the fixture does not pretend to be a real OneDrive provider.

The dashboard and OneDrive page were rendered and their pixels inspected at 1200 by 860. Folder status/notes wrap, the guide remains available, and uninstall is unavailable in the inspected configuration with OneDrive absent. The live folder check was read-only; its profile path is anonymized in the published image. Production folder paths, files, OneDrive, DNS, services and installed apps were not modified.

Release CI, security queries and extracted-package/download checks are recorded by exact commit in STATE.md and the attached release-provenance.json. Actions analysis covers GitHub Actions, not the PowerShell implementation. The shared ChatGPT URL returned only a page shell through retrieval; no conversation-content verification is claimed. The user's supplied requirements and Microsoft's current folder-backup/file-attribute documentation supplied the needed behavior contracts.

Remaining runtime limits: real Explorer/OneDrive migration and uninstall, interactive UAC, live Windows servicing, actual AppX/provider outcomes and FPS gains remain untested. Automatic registry-only folder restoration has been removed, not certified. A bounded metadata scan cannot establish that all cloud data has downloaded. The earlier audit below continues to apply.

Windows PC Toolkit 3.1.0 adds the OneDrive folder gate on October 23, 2026. Local Windows PowerShell 5.1 STA passed 614 assertions: OneDrive gate 30, base 117, Suite 48, Cleaner 57, DNS/privacy 99, repair/gaming 49, launchers 125, final gaming 24 and final Fixer 65. `Validate_All.ps1` parsed 46 PowerShell files. The new gate is `tests/Test_OneDrive.ps1`: fixture registry only, no live uninstall, no live shell-folder write, and no file deletion. A fresh dashboard load reports 66 controls and 20 optimization choices. The dashboard screenshot was rendered at 1200 by 860 and inspected. The checks below remain the 3.0.2 audit.

Windows PC Toolkit 3.0.2, local Windows 11 audit validation on October 11, 2026. [Final whole-project safety findings](docs/AUDIT_2026-10-11.md), following the [3.0.1 audit](docs/AUDIT_2026-10-10.md).

## Observed results

- **583 regression/boundary assertions passed locally** in Windows PowerShell 5.1, STA: base 116, Suite 48, Cleaner 57, DNS/privacy 99, repair/gaming 49, launchers 125, final gaming 24 and final Fixer 65. Administrative CI tokens omit 12 fixture-only principal-gate assertions, so the same suites report 571 assertions there.
- **45 PowerShell files parsed**, and launcher/DoH/safety checks passed in `Validate_All.ps1`.
- Native WPF loaded **55 controls and 19 optimization choices** from a freshly copied package in a path containing spaces, an apostrophe and non-English text.
- Actual WPF Preview button → Start-Job worker → DispatcherTimer → result text/control refresh completed.
- Actual repair button/worker/timer completed native-process success, failure and restart-required scenarios; a disposable console executable replaced DISM/SFC. The real Windows stay-awake API enabled and released its system-required flag.
- Actual read-only SFC help/error output decoded as UTF-16LE without embedded NUL characters; the disposable SFC fixture emits the same BOM-less encoding.
- Startup, app, adapter, history and health refresh buttons completed against native read-only Windows inventories.
- `docs/images/dashboard.png` rendered from the real WPF tree and visually inspected.
- Read-only native Windows probes loaded OS/hardware, essential services, startup/task and optional-AppX inventories. A redirected DNS snapshot captured schema 4 state; before/after adapter DNS and DoH configuration matched. That probe exposed native registry terminator padding, now handled in capture and historical recovery.

## Tested boundaries

The final cross-audit adds complete preflight of recovery targets, types, identities, required fields and duplicate records before writes. It tests malformed later records with zero earlier mutations, unavailable adapters/boot state, linked state and explicit snapshot paths, unique AppX hash inventories, unsafe existing state/request ACLs, legacy DNS compatibility and trailing versus embedded NUL padding. Disposable service fixtures exercise disabled-but-running recovery and failed restart cleanup. Fixer fixtures verify atomic AI/DNS backup publication, backup failures blocking changes, restore-point warning/no-op detection and Explorer cache junction refusal. Cleaner tests verify that unsafe legacy automatic imports are retired while current typed undo remains supported.

The added suites cover typed empty/single-item arrays and signed values, case-only conflicts, reviewed-only WPF optimization, linked state/cleanup/package paths, stale registry commands, AppX hash tampering, Recall post-reboot undo, restore-point no-op detection, startup/import failures, false-success console paths, service/boot/network rollback failures and originating-account guards. All 12 launchers execute actual CMD/PowerShell entrypoints with harmless target markers, exit 0/7 and Unicode/apostrophe/bracket/exclamation paths. A nonadministrative host substitutes only each fixture's principal gate; interactive UAC is not exercised.

Real disposable HKCU values and serialized journals cover String, ExpandString, Binary, MultiString, QWord, absent values and UTF-8 text. Exact undo, failed backup before mutation, intervening-user conflicts, repeated undo, interrupted pending writes, combined startup/profile journals and rollback after a partial registry action are exercised.

Actual robocopy and SHA-256 checks run on disposable package files, followed by simulated AppX removal/re-registration and Recall feature APIs. Tests cover protected packages, failed backups blocking removal, default debloat preview, feature-state journaling/undo and already-disabled features. Privacy/AI recovery injection covers denied reads/writes and failed service restart without claiming successful restore.

Real disposable filesystem tests cover old/recent/accessed files, protected data, junction escape prevention, actual deletion and successful-removal accounting. A fresh worker process verifies quoted paths and JSON results; native subprocess tests cover stderr and nonzero exit codes.

Network tests inspect real Windows cmdlet parameter contracts, then replace mutation commands with fakes. They exercise mixed per-family automatic/static modes, updating existing DoH entries, a failed Quad9 live transport test, legacy schema without a computer field, empty encryption arrays, changed interface index with preserved GUID, and missing-adapter preflight failure. They do not apply DNS to the host.

Update-repair fault injection covers failed service stop, partial cache rename, failed service restart and success; no host update folder/service is changed. Interrupted game-session injection verifies priority restoration. Cleaner category checks retain models, backups, Recall and update data as report-only.

Repair tests run the actual orchestration and native process runner with disposable executable output/exit codes. They verify DISM-before-SFC ordering, stopping after a failed command, saved output/report display, restart-required reporting, restored button availability and operation-mutex cleanup. Real P/Invoke checks prevent recurrence of the high-bit hexadecimal-to-UInt32 conversion failure. DNS tests assert that the mutation command resolves to an in-memory function before adapter-family and restore tests.

## CI and reproduction

The CI workflow runs parser/PSScriptAnalyzer gates, static toolkit validation, this native Windows regression suite in both canonical and installed friendly folder layouts, and JSON/Python validation on each pushed commit. Use the [CI run for the exact commit](https://github.com/SenjuWoo/windows-pc-toolkit/actions/workflows/ci.yml), not an older green run, as hosted evidence.

Published releases attach `release-provenance.json` with their exact commit, CI links, archive size and SHA-256. Packaging checks compare every extracted file with that commit's Git blob. Uploaded assets are downloaded again and compared byte-for-byte by SHA-256.

From the matching GitHub source checkout (tests and validators are not in the portable release ZIP):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Validate_All.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test_All.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Toolkit.ps1 -RenderPreview .\docs\images\dashboard.png
```

## Runtime limits

No live optimization profile, adapter DNS change, Windows repair, app removal/re-registration, ReTrim or update-cache rebuild was applied during development. Real AppX uninstall/re-registration, Recall servicing and provider connectivity need target-machine use to establish their runtime outcome. Package-file copy/hash verification used real disposable files; AppX and optional-feature changes were simulated. Saved policy read-back does not establish edition support or FPS gains. Deleted temp/cache files and removed app data, Recall snapshots and browser-built-in AI models are not restored by the journal. No claim of universal compatibility or measured gaming improvement is made.
