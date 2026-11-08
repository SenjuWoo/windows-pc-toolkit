# Windows PC Toolkit handoff

## Goal and current milestone

Deliver a safe, usable native Windows toolkit for fresh installs and existing PCs, including a OneDrive local-folder preflight. Preserve the configured host, personal settings and previous releases.

**3.1.2 is published and delivered.** Release commit `12ce6d7fcce69934656bbe42051f9e5e3b652597`, annotated tag `v3.1.2` (tag object `de5ad361a3e3ae450ad283d8318ce5a4b2b13078`), published 2026-11-07. The payload was downloaded again, matched to that commit blob for blob, and tested after extraction. A third portable copy is extracted beside 3.1.1 and 3.0.2.

## Published release, verified 2026-11-07

- Release: https://github.com/SenjuWoo/windows-pc-toolkit/releases/tag/v3.1.2 - not a draft, not a prerelease, target commit `12ce6d7fcce69934656bbe42051f9e5e3b652597`.
- CI run `42433174479` and CodeQL runs `42433174676` / `42433185378` are terminal-success on that exact SHA. PR `#12` checks: PowerShell/native, JSON+Python, CodeQL and Analyze (actions) all pass.
- Alerts before publication: Dependabot 0, code-scanning 0, secret-scanning 0 open. Code Quality remains unavailable and stays off.
- Assets, freshly downloaded and hashed:
  - `Windows-PC-Toolkit-3.1.2.zip` - 375,631 bytes, SHA-256 `9e8361afd54f2f6153935d4079fa18a718ddfdd78fb4bfa0720c1e9ebecb1446`, 71 payload files.
  - `release-provenance.json` - 1,495 bytes, SHA-256 `d3f3abfce2811d3ee111c7db39fd222e3fb6d3cfcfc9633d4f2a84c25c6790c6`.
  - `SHA256SUMS.txt` - 187 bytes, SHA-256 `0e98d388183845a7c9225572aedc4311a52523b0397c6ab3ec6eaeddd1e94874`.
  - All three match `SHA256SUMS.txt` and GitHub's recorded asset digests.
- Byte proof: all 71 payload files equal the raw Git blob at `12ce6d7` - 0 raw mismatches, 0 newline-normalized mismatches. Built and re-verified with the now-committed `tests/tools/build_release.py`; report `.artifacts/verify-3.1.2/downloaded-byte-verification.json`.
- Release target was published as `main`; `gh release edit v3.1.2 --target <sha>` was applied so the release metadata names the exact commit.

## Verified this session (2026-11-07, bundle v8.37.18)

- Static validation passes for 46 PowerShell files. New gate: the module version, the dashboard label (`Toolkit.xaml`) and the CHANGELOG top entry must agree, and the eight controls whose value is not self-describing must carry `AutomationProperties.Name` (OneDrive/startup/app/recovery/service grids, adapter and provider selectors, result log).
- Source checkout: **640** native assertions across nine suites - OneDrive 42, base 117, Suite 62, Cleaner 57, DNS/privacy 99, repair/gaming 49, launchers 125, final gaming 24, final Fixer 65. Log `.artifacts/verify-3.1.2/local-tests.log`; zero failures.
- Extracted published payload (tests and validator copied in only for QA): the same 640 assertions pass. Log `.artifacts/verify-3.1.2/package-tests.log`.
- Delivered copy `Z:\Backup\Ai apps\Windows pc toolkit\Windows-PC-Toolkit-3.1.2`: 71 files, 0 hash mismatches against the published ZIP, no extra files. Manifest `.artifacts/verify-3.1.2/delivered-copy-manifest.json`. `-SmokeTest` reports `66 controls, 20 optimization choices`; `Toolkit.Run.ps1 -Preview` runs.
- Real defect fixed this session: `Save-SuiteJson` used a single `[IO.File]::Replace` and threw `Unable to remove the file to be replaced` when Windows briefly held a report open - observed as an intermittent failure of the Suite audit during a full run. It now retries five times with backoff and deletes its temp file if all attempts fail; three fixture assertions cover the locked and released paths.
- Accessibility: eight controls gained `AutomationProperties.Name`; eight assertions read the names back from the loaded WPF controls, not the markup.
- Release process is now reproducible outside this machine: `tests/tools/build_release.py` and `docs/RELEASING.md` are committed (both excluded from the payload). The builder disables `core.autocrlf` for its one `git archive` call and refuses any raw mismatch.

## First unfinished step

Nothing blocks the 3.1.2 handoff. Optional follow-ups, in priority order:

1. Live end-to-end proof on a disposable VM or spare account: real OneDrive backup stop, uninstall and app-level path recovery. Everything today is fixture and read-only evidence.
2. Backlog from the 2026-10-31 blueprint review (`docs/specs/2026-10-31-blueprint-review.md`): DISM failure cause hints, a read-only BitLocker/WinRE card, Explorer window restore around the icon-cache rebuild, tiered AI controls, startup baseline diff.

## App-level paths that Windows folder mappings do not cover

A correct Windows folder mapping does not fix applications that store their own output path. The reported GoXLR case kept writing to the old OneDrive location after the shell folders were local. The toolkit does not read or change third-party app settings; re-point those apps in their own settings (or reinstall/repair) and verify a new recording lands on the local drive. Same class: OBS output and recording paths, Steam library and screenshot folders, DAW project and sample roots, browser download directories.

## Commands, diagnostics and evidence

Run from the source folder with native System32 Windows PowerShell 5.1, `-NoProfile` and `-STA`:

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./Validate_All.ps1`
- `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./tests/Test_All.ps1`
- `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./Toolkit.ps1 -SmokeTest`
- `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./Toolkit.ps1 -RenderPreview <png>`
- Read-only CLI: `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./Toolkit.Run.ps1 -Preview`

Release: follow `docs/RELEASING.md`. Build with `python tests/tools/build_release.py build <zip> <sha> --report <json>`; verify a download with `verify`. Staging lives under `_github_publish/`, which the validator and payload builder exclude. Do not publish tests or private evidence logs.

Detailed logs: `%LOCALAPPDATA%\WindowsPCToolkit\Logs`; enable with `-DebugLog` or `WINDOWS_PC_TOOLKIT_DEBUG=1`. Reports and recovery journals: `%ProgramData%\WindowsPCToolkit`. Public coverage and limits: `VALIDATION_REPORT.md`, `docs/ONEDRIVE_RECOVERY.md`. Persistent project instructions: `AGENTS.md`. The parent `WORKSPACE.md` records source/release ownership, the current release hash and Python discovery.

## Exact remaining limits

No live optimization, debloat, OneDrive uninstall, shell-folder migration, DNS change, Windows repair, servicing, AppX removal/re-registration or FPS certification was performed on this PC. Interactive UAC and real cloud-provider outcomes remain untested. Fixture success is not live repair proof. A bounded metadata scan cannot prove all cloud files were downloaded. Automatic registry-only folder restore is removed, not certified; old reports remain guarded against automatic undo. Actions analysis covers GitHub Actions, not the PowerShell implementation. No new security scanner or paid feature was enabled.

## Last known good and preservation

- Current: `Windows-PC-Toolkit-3.1.2` beside `Windows-PC-Toolkit-3.1.1` and `Windows-PC-Toolkit` (3.0.2). Keep all three; do not edit an extracted copy.
- Prior public releases remain at https://github.com/SenjuWoo/windows-pc-toolkit/releases .
- Changelog: `CHANGELOG.md`. Release note source: `docs/releases/v3.1.2.md`. Release steps: `docs/RELEASING.md`.
