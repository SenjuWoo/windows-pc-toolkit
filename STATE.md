# Windows PC Toolkit handoff

## Goal and current milestone

Deliver a safe, usable native Windows toolkit for fresh installs and existing PCs, including a OneDrive local-folder preflight. Preserve the configured host, personal settings and previous releases.

**3.4.3 is published and delivered.** Release commit `993166699b91c6ef76b298eee9537bbfe7b12228`, annotated tag `v3.4.3`, published 2026-11-08. Assets re-downloaded and matched, payload verified blob for blob against that commit, extracted into `Windows-PC-Toolkit-3.4.3` and the full suite re-run there (785 assertions). 81 files.

## Published release, verified 2026-11-08

- Release: https://github.com/SenjuWoo/windows-pc-toolkit/releases/tag/v3.4.3 - tag resolves to `993166699b91c6ef76b298eee9537bbfe7b12228`, not draft, not prerelease.
- Required checks on that SHA: Analyze (actions), Analyze (python), JSON + Python validation, PowerShell + native Windows regression checks - all success. Workflow runs CI `42518857189` and Push on main `42518857318` success.
- Alerts: Dependabot 0, code-scanning 0, secret-scanning 0. Code Quality is unavailable on this repository and is not claimed.
- `Windows-PC-Toolkit-3.4.3.zip` - 417,846 bytes, SHA-256 `eb96bf87be2daa7e2c01ddda96f9af038c12a11c8bde039300f2b7a48c833968`, 81 payload files, 0 raw blob mismatches. Provenance `79f42bef4ac2249cbcd1195a91a8fe24a4d3539837f72861bb26059acf8f5df7`; SHA256SUMS `895008e8670074b9576dff05e91dcb693e28e53b5027a4a920db6cfeb96078a9`.
- Re-downloaded assets: all three hashes match the published digests. Verified again with `build_release.py verify` against the release commit: 0 mismatches.
- Delivered copy `Z:\Backup\Ai apps\Windows pc toolkit\Windows-PC-Toolkit-3.4.3`: 785 assertions, eleven suites, exit 0; `Validate_All.ps1` passes; smoke loads 66 controls and 20 choices.
- README download and release-notes links return HTTP 200 and name v3.4.3.

## What 3.4.3 changed

- A literal catalog cache path that became a regular file is refused with "Expected a cache folder, found a file"; the root policy is checked before the file/folder split, so a cache root cannot bypass validation by changing type. Wildcard rows still delete what their pattern matches.
- Measurement applies the same rule, so such a file is never advertised as reclaimable.
- `README.md` links follow the shipped version, and `Validate_All.ps1` fails when any README link or ZIP name disagrees with `SuiteVersion`.
- Tests: 785 assertions; cache explorer 91.

## What 3.4.2 changed

- Steam shader cache no longer blocks itself across libraries: only libraries with a `shadercache` folder are listed, missing folders are skipped at validation, and an all-absent row reports "No cache folder present on this PC".
- Steam's library list is re-resolved immediately before deletion; a library removed, unplugged or repointed after the scan is refused and its files survive.
- Tests: 779 assertions (85 cache explorer).

## What 3.4.1 changed

- Steam shader cache is cleanable through a policy that accepts exactly the folders Steam reports live; the Program Files guard is unchanged for everything else.
- VRChat cache freshness fails closed on absent, unreadable or moved configuration.
- Portable MO2 detection with identity verification; MO2/Vortex/DynDOLOD logs gated by their owning process at scan, at clean and before each file; Skyrim VR checks `sksevr_loader`.
- Catalog 22 categories: 13 deletable, 9 report-only. Codex catalog cache and Claude shell snapshots are measured and kept.
- Tests: 770 assertions (76 cache explorer, 35 Skyrim).

## What 3.4.0 changed

- One cleanup-root validator (drive roots, Windows/Program Files/ProgramData, profile/AppData/LocalLow roots, user libraries, game libraries, cloud-sync, ancestors of all of those); custom roots must also be named as a cache.
- VRChat `cache_directory` honoured only when it passes that validator and re-read at execution; a change is refused with "rescan".
- Every container target re-checked immediately before deletion; junctions never traversed.
- Skyrim/modding cleanup re-derives processes, Documents root, cloud state and the approved target at execution; a forged row cannot authorize anything.
- Coverage: MO2 logs, Vortex logs, DynDOLOD/TexGen/LODGen logs, Yarn, pnpm (report), GPU/DirectX shader caches (strict, opt-in). 20 categories: 13 deletable, 7 report-only.
- Tests: 743 assertions (56 cache explorer, 28 Skyrim).

## What 3.3.0 changed

- Cache scanner: wildcard directory patterns resolved as directories; bounded streaming walk; per-file age checks; eligible vs discovered bytes; unique report names; detail view with paths/source/impact; Steam from registry + every libraryfolders.vdf entry; VRChat cache_directory; Steam staging and Epic webcache report-only; Gradle/UE closed-app checks.
- Structure: `CacheExplorer.ps1` and `SkyrimCleanup.ps1`; `PC_Cleaner.ps1` 943 lines; cleaner 1.3.0.
- Skyrim menu `[9]`: SKSE/Papyrus logs for SE/AE and VR, SAFE/HARD, `.log`/`.logN` only, one revalidated Documents exception, cloud-synced Documents report-only, MO2/Vortex measured only.
- Tests: 716 assertions in eleven suites (Cache Explorer 41, Skyrim 16).

## What 3.2.0 adds

- PC Cleaner 1.2.0 Cache Explorer on menu `[8]`: read-only bounded scan of 16 catalog categories (12 deletable, 4 report-only) for AI, gaming and developer caches, with per-row source, risk, age, rebuild cost, JSON export and typed confirmation before deletion.
- Deletable categories: Antigravity caches (signature-gated), Steam shadercache/temp per library, VRChat Cache-WindowsPlayer, Epic webcache, Roblox/Minecraft aged logs, pip/npm/NuGet, Unreal DDC, Gradle.
- Report-only: Codex, Claude and Hermes homes, Unity project libraries.
- Four new gates on the existing choke point: Delete=false refuses, signature folder required, running app blocks, protected folder inside a cache root refuses the whole root. `AgeDays` rechecked per item.
- `tests/Test_CacheExplorer.ps1`: 30 fixture checks. Native suite 689 assertions in ten suites.

## What 3.1.4 fixes

- 3.1.3's MMCSS conditional write could not work. The six `Tasks\Games` values were in `$targets`, so the blanket removal loop deleted them before the comparison, and every repair rewrote all five "defaults". The defaults were wrong too: this Windows 11 reports `Scheduling Category=High`, `SFIO Priority=High`, `Background Only=False`, and Microsoft documents ranges rather than one shipping default.
- The repair now journals those six values, skips them by path in the deletion loop and never rewrites them. The redundant `Clock Rate` removal is gone; other legacy targets are still removed after the snapshot.
- The new stateful regression (real HKCU fixture, real snapshot, real removal loop) fails on the shipped 3.1.3 module with `TEST FAILED: A custom MMCSS value survives the repair` and passes on 3.1.4. Proof lives in `.artifacts/verify-3.1.4/old-fails.log`.

## What 3.1.3 changed, and which review findings were real

- **Confirmed (optimizer):** `Invoke-LegacyOptimizerRepair` forced SysMain to Automatic and called `Enable-GamingSupportedOffloads`, which turned RSS/RSC on for every capable adapter. Both are configuration, not a v3.x leftover, and the pre-tweak value was never recorded. The repair now reports SysMain and leaves it, no longer enables offloads, and the offload helper is deleted. MMCSS Games values are written only when they differ from Microsoft's documented defaults; the snapshot done first still restores a custom value through undo. `Invoke-LegacyNetworkCleanup` no longer enables offloads either.
- **Confirmed (DNS):** the dashboard recorded `Get-LatestSnapshot` after a DNS change, so a parallel operation could make undo point at the wrong file. `Set-Provider` and `Reset-Dhcp` now return the exact snapshot they created and the worker stores that path; both entry points and `Restore-Snapshot` take the shared `Global\WindowsPCToolkit.SafeOperation` mutex, which is re-entrant for the worker's own thread and refuses a second console.
- **Confirmed but narrower than reported (OneDrive):** a missing Explorer `Shell Folders` value was treated as a local folder. It cannot be proven local, so it is now unverified: lock, uninstall and restore stay blocked and the row explains that opening Explorer rebuilds the cache. No path is rewritten. The authoritative value is still `User Shell Folders`, so a missing cache is not evidence of a redirect.
- **Rejected as a false alarm:** "Background Only = True is questionable for the Games task". It is Microsoft's documented default for that profile; the value is only written when it already differs.

## Verified this session (2026-11-07)

- Static validation passes for 46 PowerShell files, including the version-sync and accessible-name gates.
- Source checkout: **689** native assertions across ten suites - OneDrive 45, base 117, Suite 62, Cleaner 57, Cache Explorer 30, DNS/privacy 104, repair/gaming 49, launchers 125, final gaming 35, final Fixer 65. Log `.artifacts/verify-3.2.0/local-tests.log`; zero failures.
- Extracted published payload (tests and validator copied in only for QA): the same 689 assertions pass. Log `.artifacts/verify-3.2.0/package-tests.log`. Payload smoke test reports `66 controls, 20 optimization choices`; `Toolkit.Run.ps1 -Preview` runs.
- New regressions: custom MMCSS value reset and matching value untouched, no service or adapter mutation during a cleanup, missing shell cache blocks the gate, exact snapshot path returned by both DNS entry points, real second-thread mutex refusal with recovery after release.

## First unfinished step

Nothing blocks the 3.2.0 handoff. Optional follow-ups, in priority order:

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

- Current: `Windows-PC-Toolkit-3.2.0` (74 files, matches the published ZIP). 3.1.2, 3.1.3 and 3.1.4 remain on disk; 3.0.2 and 3.1.1 are absent and were not re-created; every release remains downloadable from GitHub. Do not edit an extracted copy.
- Prior public releases remain at https://github.com/SenjuWoo/windows-pc-toolkit/releases .
- Changelog: `CHANGELOG.md`. Release note source: `docs/releases/v3.2.0.md`. Release steps: `docs/RELEASING.md`.
