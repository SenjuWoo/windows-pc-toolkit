# Windows PC Toolkit handoff

## Goal and current milestone

Deliver a safe, usable native Windows toolkit for fresh installs and existing PCs, including a OneDrive local-folder preflight. Preserve the configured host, personal settings and previous releases.

**3.1.1 is published and delivered.** Source commit `018bc6414b02e4838f72074d560c569245d7d3ac`, annotated tag `v3.1.1` (tag object `5efc8c1a4f501fef0dc5df5af6839c8b8ff1066f`), GitHub release published 2026-10-24T16:10:31Z. The published payload was downloaded again, matched to that commit blob-for-blob, and tested after extraction. A separate portable copy is extracted beside the preserved 3.0.2 release.

## Published release, verified 2026-10-24

- Release: https://github.com/SenjuWoo/windows-pc-toolkit/releases/tag/v3.1.1 - not a draft, not a prerelease, target commit `018bc6414b02e4838f72074d560c569245d7d3ac`.
- CI run `40109276424` and CodeQL Actions analysis run `40109275954` are terminal-success on that exact SHA. Check runs on the SHA: `PowerShell + native Windows regression checks`, `JSON + Python validation`, `Analyze (actions)` - all success.
- Alert queries after publication: Dependabot 0, code-scanning 0, secret-scanning 0 open. Code Quality remains unavailable and stays off.
- Assets, freshly downloaded and hashed:
  - `Windows-PC-Toolkit-3.1.1.zip` - 371,753 bytes, SHA-256 `ae9873780087978153874032eb90d3b795397f948a235a62c806effe95ce3a1e`, 69 payload files.
  - `release-provenance.json` - 1,446 bytes, SHA-256 `6b04989061f7938dbb763fcf004d44a218bfd91294b4bd86c1ecd33330f9e02a`.
  - `SHA256SUMS.txt` - 187 bytes, SHA-256 `7c3b94d8075c7eaffe7a3262f9b54d888b4845271dbd9a4db1ad425735759df8`.
  - All three match `SHA256SUMS.txt` and GitHub's recorded asset digests.
- Byte proof: every one of the 69 payload files matches the raw Git blob at the release commit - 0 raw mismatches, 0 newline-normalized mismatches. Re-verified independently from the downloaded ZIP with `.artifacts/resume-2026-10-24/release_bytes.py verify`; report `.artifacts/verify-3.1.1/downloaded-byte-verification.json`.
- Release notes were edited after publication to replace two relative links that rendered as 404s with commit-pinned absolute URLs. Both now return 200. No asset, tag or commit was changed.

## Verified this session (2026-10-24, continuation)

- Static validation passes for 46 PowerShell files (`Validate_All.ps1`, repo and payload layouts).
- Source checkout: 629 native assertions across nine suites - OneDrive 42, base 117, Suite 51, Cleaner 57, DNS/privacy 99, repair/gaming 49, launchers 125, final gaming 24, final Fixer 65. Log `.artifacts/verify-3.1.1/head-native-tests.log`; zero failures.
- Extracted published payload (with the repository's `tests/` and `Validate_All.ps1` added only for QA): the same 629 assertions pass. Log `.artifacts/verify-3.1.1/package-native-tests.log`; zero failures.
- Delivered portable copy `Z:\Backup\Ai apps\Windows pc toolkit\Windows-PC-Toolkit-3.1.1`: 69 files, 0 hash mismatches against the published ZIP, no extra files. Manifest `.artifacts/verify-3.1.1/delivered-copy-manifest.json`.
- Shipped copy smoke test: `Dashboard loaded: 66 controls, 20 optimization choices.` Read-only CLI preview (`Toolkit.Run.ps1 -Preview`) runs from the delivered copy.
- Shipped OneDrive page rendered at 1200x860 from the delivered copy; the PNG is byte-identical (SHA-256 `3ae271d702d8dd297be666e9c150dbe2dc321bf0ed2b95f5edeb3d966b15c088`) to the published `docs/images/onedrive.png`. Pixels were not re-inspected in this continuation; identity with the reviewed screenshot is the evidence.
- Code review of the 3.1.1 diff confirms the release-note claims: uncertain, invalid, linked, UNC or missing paths and non-string registry kinds resolve to `Unknown` and block the policy lock and uninstall shortcut; modern local aliases (`{F42EE2D3-...}` Documents, `{0DDD015D-...}` Pictures, `{A0C69A99-...}` Music, `{35286A68-...}` Videos) are checked in both `User Shell Folders` and `Shell Folders`; cloud recall flags are counted before reparse filtering and every skipped or inaccessible path marks the scan incomplete; `Invoke-SuiteOneDriveFolderRestore` refuses before any write and the worker still routes legacy `RestoreOneDriveFolders` requests into that refusal; the dashboard rechecks live state on the uninstall click.
- The preserved `Windows-PC-Toolkit` 3.0.2 folder was not touched (66 files, UI label v3.0.2).

## First unfinished step

Nothing blocks the 3.1.1 handoff. The 2026-10-31 modernization blueprint was reviewed against the shipped source and **no code was applied**: none of its claimed defects reproduces here, and its architectural items are already covered by the worker-process design, the compensation-retaining undo journals and the 629-assertion harness. Verdict and the optional backlog: `docs/specs/2026-10-31-blueprint-review.md` (spec files are excluded from the payload, so this needed no release).

Optional follow-ups, in priority order:

1. Live end-to-end proof on a disposable VM or spare account: real OneDrive backup stop, uninstall, and app-level path recovery. Everything today is fixture and read-only evidence.
2. If a future release ships, consider adding the app-level storage-path note (below) to `docs/ONEDRIVE_RECOVERY.md`; it is deliberately not in 3.1.1 because that would change a shipped file after publication.

## App-level paths that Windows folder mappings do not cover

A correct Windows folder mapping does not fix applications that store their own output path. The reported GoXLR case kept writing to the old OneDrive location after the shell folders were local. The toolkit does not read or change third-party app settings; re-point those apps in their own settings (or reinstall/repair) and verify a new recording lands on the local drive. Same class: OBS output and recording paths, Steam library and screenshot folders, DAW project and sample roots, browser download directories.

## Commands, diagnostics and evidence

Run from the source folder with native System32 Windows PowerShell 5.1, `-NoProfile` and `-STA`:

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./Validate_All.ps1`
- `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./tests/Test_All.ps1`
- `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./Toolkit.ps1 -SmokeTest`
- `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./Toolkit.ps1 -RenderPreview <png>`
- Read-only CLI: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./Toolkit.Run.ps1 -Preview`

Release rebuild helper: `.artifacts/resume-2026-10-24/release_bytes.py` (`build` / `verify`). It uses `git -c core.autocrlf=false -c core.eol=lf archive` so payload bytes match raw blobs. Staging stays under `_github_publish/`, which the validator excludes. Do not publish tests or private evidence logs.

Detailed logs: `%LOCALAPPDATA%\WindowsPCToolkit\Logs`; enable with `-DebugLog` or `WINDOWS_PC_TOOLKIT_DEBUG=1`. Reports and recovery journals: `%ProgramData%\WindowsPCToolkit`. Public coverage and limits: `VALIDATION_REPORT.md`, `docs/ONEDRIVE_RECOVERY.md`, `docs/specs/2026-10-24-onedrive-review.md`. Persistent project instructions: `AGENTS.md`. The parent `WORKSPACE.md` records source/release ownership, the current release hash and Python discovery.

## Exact remaining limits

No live optimization, debloat, OneDrive uninstall, shell-folder migration, DNS change, Windows repair, servicing, AppX removal/re-registration or FPS certification was performed on this PC. Interactive UAC and real cloud-provider outcomes remain untested. Fixture success is not live repair proof. A bounded metadata scan cannot prove all cloud files were downloaded. Automatic registry-only folder restore is removed, not certified; old reports remain guarded against automatic undo. Actions analysis covers GitHub Actions, not the PowerShell implementation. No new security scanner or paid feature was enabled.

## Last known good and preservation

- Current: `Windows-PC-Toolkit-3.1.1` (this release) beside `Windows-PC-Toolkit` (3.0.2). Keep both; do not edit either extracted copy.
- Prior public releases remain at https://github.com/SenjuWoo/windows-pc-toolkit/releases . The 3.1.0 ZIP and assets are retained in `.artifacts/resume-2026-10-24/published-3.1.0` for comparison only.
- Changelog: `CHANGELOG.md`. Release note source: `docs/releases/v3.1.1.md`.
