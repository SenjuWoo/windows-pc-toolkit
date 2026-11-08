# Windows PC Toolkit handoff

## Goal and current milestone

Deliver a safe, usable native Windows toolkit for fresh installs and existing PCs, including a OneDrive local-folder preflight. Preserve the configured host, personal settings and previous releases.

**3.1.3 is published and delivered.** Release commit `3f9ebb558e69cd7c920cb76b3f0fb659ef2d9805`, annotated tag `v3.1.3` (tag object `3733acdec458298af4cacda144b00d3fdd7b9e10`), published 2026-11-07. The payload was downloaded again, matched to that commit blob for blob, and tested after extraction. A portable copy is extracted at `Windows-PC-Toolkit-3.1.3`; the earlier 3.0.2 and 3.1.1 extracts are no longer present, and `3.1.2` sits next to it. All previous releases remain on GitHub.

## Published release, verified 2026-11-07

- Release: https://github.com/SenjuWoo/windows-pc-toolkit/releases/tag/v3.1.3 - not a draft, not a prerelease, tag resolves to `3f9ebb558e69cd7c920cb76b3f0fb659ef2d9805`.
- CI run `42438007389` and CodeQL analysis run `42438007091` are terminal-success on that exact SHA. PR `#15` checks: PowerShell/native, JSON+Python, CodeQL and Analyze (actions) all pass.
- Alerts before publication: Dependabot 0, code-scanning 0, secret-scanning 0 open. Code Quality remains unavailable and stays off.
- Assets, freshly downloaded and hashed:
  - `Windows-PC-Toolkit-3.1.3.zip` - 378,702 bytes, SHA-256 `19f85de3888f7cb53f16e53cb8f99de9c5fdca97eed0dc91386e85f31dcae4bf`, 72 payload files.
  - `release-provenance.json` - 1,452 bytes, SHA-256 `2337844148a228cd3912459e90edf734611cc1c269d7a562561826e18dc7e963`.
  - `SHA256SUMS.txt` - 185 bytes, SHA-256 `96d1c39df9ccbcbf4d599bc0964163040858d3334145923547272a52285744e7`.
  - All three match `SHA256SUMS.txt` and GitHub's recorded asset digests.
- Byte proof: all 72 payload files equal the raw Git blob at `3f9ebb5` - 0 raw mismatches, 0 newline-normalized mismatches. Report `.artifacts/verify-3.1.3/verify-downloaded.json`.

## What 3.1.3 changes, and which review findings were real

- **Confirmed (optimizer):** `Invoke-LegacyOptimizerRepair` forced SysMain to Automatic and called `Enable-GamingSupportedOffloads`, which turned RSS/RSC on for every capable adapter. Both are configuration, not a v3.x leftover, and the pre-tweak value was never recorded. The repair now reports SysMain and leaves it, no longer enables offloads, and the offload helper is deleted. MMCSS Games values are written only when they differ from Microsoft's documented defaults; the snapshot done first still restores a custom value through undo. `Invoke-LegacyNetworkCleanup` no longer enables offloads either.
- **Confirmed (DNS):** the dashboard recorded `Get-LatestSnapshot` after a DNS change, so a parallel operation could make undo point at the wrong file. `Set-Provider` and `Reset-Dhcp` now return the exact snapshot they created and the worker stores that path; both entry points and `Restore-Snapshot` take the shared `Global\WindowsPCToolkit.SafeOperation` mutex, which is re-entrant for the worker's own thread and refuses a second console.
- **Confirmed but narrower than reported (OneDrive):** a missing Explorer `Shell Folders` value was treated as a local folder. It cannot be proven local, so it is now unverified: lock, uninstall and restore stay blocked and the row explains that opening Explorer rebuilds the cache. No path is rewritten. The authoritative value is still `User Shell Folders`, so a missing cache is not evidence of a redirect.
- **Rejected as a false alarm:** "Background Only = True is questionable for the Games task". It is Microsoft's documented default for that profile; the value is only written when it already differs.

## Verified this session (2026-11-07)

- Static validation passes for 46 PowerShell files, including the version-sync and accessible-name gates.
- Source checkout: **653** native assertions across nine suites - OneDrive 45, base 117, Suite 62, Cleaner 57, DNS/privacy 104, repair/gaming 49, launchers 125, final gaming 29, final Fixer 65. Log `.artifacts/verify-3.1.3/local-tests.log`; zero failures.
- Extracted published payload (tests and validator copied in only for QA): the same 653 assertions pass. Log `.artifacts/verify-3.1.3/package-tests.log`. Payload smoke test reports `66 controls, 20 optimization choices`; `Toolkit.Run.ps1 -Preview` runs.
- New regressions: custom MMCSS value reset and matching value untouched, no service or adapter mutation during a cleanup, missing shell cache blocks the gate, exact snapshot path returned by both DNS entry points, real second-thread mutex refusal with recovery after release.
- Delivered copy `Z:\Backup\Ai apps\Windows pc toolkit\Windows-PC-Toolkit-3.1.3`: 72 files, hashes match the published ZIP, `-SmokeTest` passes.

## First unfinished step

Nothing blocks the 3.1.3 handoff. Optional follow-ups, in priority order:

1. Live end-to-end proof on a disposable VM or spare account: real OneDrive backup stop, uninstall and app-level path recovery, plus a gaming-profile apply and undo. Everything today is fixture and read-only evidence.
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

Release: follow `docs/RELEASING.md`. Build with `python tests/tools/build_release.py build --report <json> <zip> <sha>`; verify a download with `verify`. Staging lives under `_github_publish/`, which the validator and payload builder exclude. Do not publish tests or private evidence logs.

Detailed logs: `%LOCALAPPDATA%\WindowsPCToolkit\Logs`; enable with `-DebugLog` or `WINDOWS_PC_TOOLKIT_DEBUG=1`. Reports and recovery journals: `%ProgramData%\WindowsPCToolkit`. Public coverage and limits: `VALIDATION_REPORT.md`, `docs/ONEDRIVE_RECOVERY.md`. Persistent project instructions: `AGENTS.md`. The parent `WORKSPACE.md` records source/release ownership, the current release hash and Python discovery.

## Exact remaining limits

No live optimization, debloat, OneDrive uninstall, shell-folder migration, DNS change, Windows repair, servicing, AppX removal/re-registration or FPS certification was performed on this PC. Interactive UAC and real cloud-provider outcomes remain untested. Fixture success is not live repair proof. A bounded metadata scan cannot prove all cloud files were downloaded. Automatic registry-only folder restore is removed, not certified; old reports remain guarded against automatic undo. Actions analysis covers GitHub Actions, not the PowerShell implementation. No new security scanner or paid feature was enabled. A mutex proves mutual exclusion inside Windows, not that a third-party DNS tool respects it.

## Last known good and preservation

- Current: `Windows-PC-Toolkit-3.1.3` (72 files, matches the published ZIP). `Windows-PC-Toolkit-3.1.2` is still on disk; 3.0.2 and 3.1.1 are absent and were not re-created; every release remains downloadable from GitHub. Do not edit an extracted copy.
- Prior public releases remain at https://github.com/SenjuWoo/windows-pc-toolkit/releases .
- Changelog: `CHANGELOG.md`. Release note source: `docs/releases/v3.1.3.md`. Release steps: `docs/RELEASING.md`.
