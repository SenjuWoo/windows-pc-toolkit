# Changelog

## Toolkit 3.4.3 (2026-11-08)

- A catalog path that was a cache folder at scan time and a regular file at clean time no longer falls through to plain-file deletion. Literal paths now carry a folder expectation, the root policy is checked before the file/folder split, and a file found where a cache folder belonged is kept with the note "Expected a cache folder, found a file".
- Measurement applies the same rule, so such a file is not advertised as reclaimable. Wildcard log rows still delete the files their pattern matches.
- `README.md` advertised a newer download than its links pointed at; all download and release-notes URLs now name the shipped version, and `Validate_All.ps1` fails when any README link or ZIP name disagrees with `SuiteVersion`.
- Tests: 91 cache explorer checks (was 85), including the directory-to-file crossing and a wildcard row that still cleans.

## Toolkit 3.4.2 (2026-11-08)

- Fixed the Steam shader cache blocking itself across libraries: the catalog listed `steamapps\shadercache` for every Steam library even when the folder did not exist, and validation rejected the missing ones, so one empty library disabled the whole category while the scan still showed bytes. Only libraries with a shader cache are listed now, and missing folders are skipped instead of refusing the row.
- Steam roots are re-resolved immediately before deletion instead of trusting the scan. A library removed, unplugged or repointed after the scan is refused and its files survive; a library that only exists in the stale row is skipped.
- A row whose folders are all absent reports "No cache folder present on this PC" rather than appearing cleanable.
- Tests: 85 cache explorer checks (was 76), covering one populated plus one empty library, two populated libraries, a changed library mapping, a forged folder and a junction. Suite total 779.

## Toolkit 3.4.1 (2026-11-08)

- Fixed the Steam shader-cache row: it was discovered under `Program Files (x86)` and then refused by the Program Files guard, so it could never be cleaned. A Steam policy now accepts exactly the shadercache folders Steam reports live; the guard is unchanged for every other path, and `steamapps`, `common`, `compatdata`, installers and manifests stay out of reach.
- Scan and deletion share that policy, so no category is advertised as cleanable when the delete would refuse it.
- VRChat cache freshness now fails closed: one resolver reports `absent`, `default`, `custom` or `invalid`, and a moved, removed, unreadable or path-less config refuses the row with "rescan" instead of being treated as agreement. The documented default still works when no custom path was set.
- Skyrim/modding: portable MO2 instances are detected (`logs` under the selected root) and a root must prove it is MO2 through its own files. MO2, Vortex and DynDOLOD/TexGen/LODGen logs are gated by their owning process at scan, at clean and immediately before each deletion. Skyrim VR checks `sksevr_loader`.
- Catalog is 22 categories (13 deletable, 9 report-only). Codex catalog cache and Claude shell snapshots are measured but report-only: both live in homes protected wholesale, and the guard was not weakened for them.
- `pc-cleaner/README.md` headings now match the shipped versions, with a table defining SAFE, CAREFUL, STRICT and REPORT.

## Toolkit 3.4.0 (2026-11-08)

- One cleanup-root validator now decides what may be deleted as a cache: drive roots, Windows/Program Files/ProgramData, profile, AppData and LocalLow roots, user libraries, game libraries and cloud-sync folders are refused, as is any path that contains one of them. A custom root must also be named as a cache.
- VRChat honours `config.json` `cache_directory` only when it passes that validator; an unsafe or unparseable value is measured and kept, never replaced by another location. The path is re-read at execution time, so a config change after the scan is refused.
- Every container target is re-checked for links, reserved locations and containment immediately before deletion, and a refusal marks the row skipped with its reason.
- Skyrim and modding cleanup re-derive processes, the Documents known folder, cloud-sync state and the exact approved target at execution time. A stale or forged scan row cannot authorize a deletion; a moved folder is refused. `Remove-SkyrimLogFile` no longer accepts a caller-supplied root or pattern.
- New modding coverage: MO2 `logs` (`mo_interface*.log`, `usvfs-*.log`), Vortex `vortex*.log`, DynDOLOD/TexGen/LODGen `*_log.txt`. Portable installs are listed only when their folder is supplied; mods, profiles, overwrite, downloads, state and generated LOD stay.
- New cache categories: Yarn (SAFE), pnpm store (REPORT), GPU driver shader caches and DirectX `D3DSCache` (STRICT, opt-in). Catalog is 20 categories: 13 deletable, 7 report-only.
- `pc-cleaner/README.md` corrected: Steam staging and Epic webcache are report-only, as the catalog always said. Cleaner header version matches the shipped version.

## Toolkit 3.3.0 (2026-11-07)

- Cache Explorer fixes: a wildcard directory pattern (Epic style) is measured as directories instead of as files, so the scan no longer reports zero bytes for a cache it would clean; the scan enumerates depth-first and stops at the cap instead of materialising the whole tree; age rules are applied to each file immediately before deletion, so a fresh file inside an old folder survives and the estimate matches the bytes removed; the scan shows eligible bytes next to total found, unique report names, and a detail view with every path, source and rebuild impact.
- Steam discovery reads the registry and every `libraryfolders.vdf` entry and validates each root as a local fixed drive. VRChat honours a configured local `cache_directory`. Steam staging temp and the Epic webcache folder are now report-only: staging can hold an unfinished update, and the browser `WebCache` guard also covers Epic's folder name.
- Gradle and Unreal caches require their editor or JVM to be closed.
- `PC_Cleaner.ps1` is 943 lines again: the catalog, scanner and explorer live in `CacheExplorer.ps1`, and the new Skyrim cleaner in `SkyrimCleanup.ps1`.
- New Skyrim & Modding Cleanup (menu `[9]`): SKSE and Papyrus diagnostic logs under the Windows Documents known folder for Skyrim SE/AE and Skyrim VR, SAFE (older than 7 days) or HARD (any age, game and tools closed). Only `.log`/`.logN` files are eligible; saves, `.ini`, `.json`, `.toml`, `.yaml`, `.dll`, `.pex`, `.psc` and unknown types stay, including inside the SKSE folder. This is the single approved Documents exception, revalidated per file: approved root, direct child, log pattern, no link in any parent, regular file. Cloud-synced Documents folders are report-only, and MO2/Vortex data folders are measured without deletion.

## Toolkit 3.2.0 (2026-11-07)

- PC Cleaner 1.2.0 adds a Cache Explorer (menu `[8]`) for AI, gaming and developer caches. It scans read-only, names the source and rebuild cost of every category, exports a JSON report, and deletes only after a typed confirmation.
- Deletable: Antigravity editor caches (only when its `User` folder proves the layout), Steam `shadercache` and `steamapps` temp per library with Steam closed, VRChat `Cache-WindowsPlayer`, Epic `Saved` webcache folders with the launcher closed, Roblox and Minecraft logs older than seven days, pip/npm/NuGet download caches, and Unreal DDC or Gradle caches as STRICT choices.
- Report-only: Codex (`CODEX_HOME`), Claude (`CLAUDE_CONFIG_DIR`) and Hermes homes, plus Unity project libraries. Sessions, SQLite state, memories, skills, `.claude.json`, the Codex tmp helper folder, `state.db` and model stores are never in scope.
- Guards added on top of the existing choke point: `Delete=false` refuses, a required signature folder must exist, a running app blocks its category, a cache root holding a protected folder is refused whole, and `AgeDays` is rechecked per item before removal.
- Tests: new `tests/Test_CacheExplorer.ps1` with 30 fixture checks (junction, locked file, protected names, report-only, idempotency, overlap accounting, post-scan rename, export). No live cache was touched.


## Toolkit 3.1.4 (2026-11-07)

- The legacy optimizer repair no longer deletes or rewrites the MMCSS Games block. The previous conditional write could never work: the blanket removal loop deleted those six values first, so every repair rewrote them from a guess. The block is now journaled for undo, skipped by the deletion loop and left untouched, because Microsoft documents the value ranges while the shipping defaults differ by build. Other legacy overrides are still removed with the same snapshot.
- Regression coverage runs the real snapshot-then-remove order against a disposable HKCU fixture: a custom value, a non-default scheduling category, a custom Clock Rate and a missing value all survive, the six values appear in the journal, a mid-operation failure restores from it, and a failed snapshot removes nothing.

## Toolkit 3.1.3 (2026-11-07)

- Legacy optimizer repair no longer forces SysMain startup or turns on RSS/RSC for each adapter. A cleanup removes the v3.x overrides it can identify, reports the current SysMain state and leaves adapter offloads at the driver setting, because the value before the old tweak was never recorded. MMCSS Games values are written only when they differ from Microsoft's documented defaults, and the snapshot taken first still restores a custom setup.
- The OneDrive gate treats a missing Explorer `Shell Folders` cache entry as unverified instead of assuming the folder is local, so the lock and uninstall actions stay blocked until Explorer has written that cache.
- Encrypted DNS reports the exact snapshot it created: `Set-Provider` and `Reset-Dhcp` return the path, the dashboard stores that path for undo, and standalone DNS changes take the shared operation mutex so a console and the dashboard cannot mutate DNS at the same moment.

## Toolkit 3.1.2 (2026-11-07)

- Name the OneDrive, startup, app, recovery and service grids, the adapter and DNS provider selectors, and the result log for screen readers. Buttons already expose their visible text; these controls were announced only by type.
- Fail validation when the module version, the dashboard label and the changelog's top entry disagree, so a build cannot misreport its own version.
- Publish the release builder (`tests/tools/build_release.py`) and the release steps (`docs/RELEASING.md`) with the repository, so the payload-to-commit check recorded in `release-provenance.json` can be reproduced outside the author's machine.
- No change to any optimization, repair, cleanup, debloat or DNS action.

## Toolkit 3.1.1 (2026-10-24)

- Fix the OneDrive preflight accepting relative, unresolved, invalid, missing or linked locations as safe custom folders. Check the modern local Documents/Pictures/Music/Videos aliases too; preserve valid custom local directories.
- Refresh folder status when uninstall is clicked, so a previous successful check cannot authorize an uninstall shortcut after backup settings change.
- Count cloud-file recall flags before skipping reparse points. Bound all inspected entries and explicitly report skipped, inaccessible and virtual directories as incomplete; never follow them or open file contents.
- Withdraw the automatic registry-only folder restore introduced in 3.1.0: it could redirect apps to a nonexistent destination and did not prove complete shell migration. Old requests now refuse before writes. Recovery instructions replace that action; existing files and reports remain intact.
- Correct fresh-install guidance: already-local folders need no OneDrive sign-in. Explain Microsoft's Only on my PC choice and the need to download online-only data first.
- Add regression cases for these failures and persistent project instructions. Keep the previous 3.0.2 extracted release unchanged.

## Toolkit 3.1.0 (2026-10-23)

- Add an OneDrive folders page. It reads Desktop, Documents, Pictures, Music and Videos and says whether each one is on this PC.
- Refuse the known-folder lock, and do not offer uninstall, while any of those folders still point at OneDrive. The user has to sign in and choose Only on my PC first. Uninstalling first leaves the old paths behind.
- Lock folders with the documented `KFMBlockOptIn` policy value 1 only after they are already local. This does not move or delete files. `KFMBlockOptOut`, `KFMSilentOptIn` and `KFMOptInWithWizard` block the lock.
- If OneDrive is already gone and a folder still points at it, restore only those locations to the local profile and leave the files where they are. That report is not undone.
- The toolkit does not run an OneDrive uninstaller. When the folders are local and the app is installed, it opens Installed apps.
- The OneDrive page wraps the warning, keeps folder paths readable, and leaves uninstall and restore disabled until the check allows them.

## Toolkit 3.0.2 (2026-10-11)

- Cross-audit the whole kit again; validate complete recovery records before writes and reject unsupported targets, malformed values, duplicate records and unavailable original adapters.
- Require exact AppX hash inventories and check permissions on existing Suite state directories.
- Reject linked snapshot and Explorer cache paths; preserve skipped-file and Explorer restart failures in results.
- Verify repair snapshots before changes and require a new native restore-point sequence before reporting success.
- Correct disabled-but-running service recovery, incomplete DNS schema handling and obsolete Edge telemetry policy.
- Retire unsafe automatic legacy file/whole-registry-key recovery while preserving its backup files for manual review; keep current typed undo.
- Handle native DNS registry terminator padding and recover historical padded address arrays without accepting embedded corruption.
- Add focused failure-path regressions; keep optimizerDuck recommendation, safe default scope and existing recovery data. See [the cross-audit](docs/AUDIT_2026-10-11.md).

## Toolkit 3.0.1 (2026-10-10)

- Audited all components, wrappers, shared modules, dashboard/worker, recovery, tests, launchers, CI and documentation before further feature expansion. Detailed findings: [audit](docs/AUDIT_2026-10-10.md).
- Cleaner 1.1.1: make Windows.old truly report-only; prevent cleanup through ancestor junctions; align Temp scans with aged-file deletion; preserve replacements during registry/legacy recovery; report failed cache commands and retain unique logs.
- DNS 2.2.1: correct Quad9 secondary IPv6 to `2620:fe::9`; require typed DoH APIs; preflight address families and restore modes; verify writes, removals and DHCP reset with rollback on failure.
- Privacy 2.1.1: save the identity required by undo; verify snapshot inventories and writes; preserve typed arrays and delayed service startup; surface denied writes and require confirmation for legacy identity-less backups.
- Fixer 7.2.1 and Gaming 5.0.1: repair summary exit crash; retain native command verdicts; stop false-success repair/undo paths; narrow Store restore to the current user; scope and validate recovery snapshots; protect shader paths and preserve NTP configuration.
- Dashboard/core: preview reviewed selections; accept reviewed-only runs; lock profile controls while busy; retain worker startup/partial failure results; compare registry strings exactly; reject empty undo and linked state paths; use literal scheduled-task objects; verify stored AppX file hashes before reinstall.
- Launchers: replace service-dependent elevation checks, quoted-path interpolation and timed UAC flags with principal checks and waiting on the child process; propagate exit codes.
- Add native failure-path suites to CI in both folder layouts. Add bounded optional debug diagnostics under `%LOCALAPPDATA%\WindowsPCToolkit\Logs`. No new optimizer/debloat features or dependencies.

## Toolkit 3.0.0 (2026-10-01)

- New native WPF dashboard: Optimize, Startup/tasks, App debloat, Encrypted DNS, Recovery/reports and Repair/tools. One-click ten-action recommended profile, nine optional choices and reviewed app/startup selections in one journal.
- Typed before-write registry backups, read-back, conflict-aware/idempotent undo, per-action failure reporting and partial registry rollback. UTF-8 state and quoted Unicode/space/apostrophe paths.
- Startup Run entries and third-party boot/logon tasks; consumer-AppX allowlist with verified package copies before removal. Essential packages stay protected. App-data and cache deletion limits are explicit.
- DNS 2.2: modify existing DoH entries in place, GUID-based adapter restore, per-family automatic/static state, affected-entry snapshots, failed live Quad9 checks fail verification, AdGuard profile and immediate removal of new Mullvad applies ahead of public-service retirement; legacy backups remain restorable.
- Cleaner 1.1: aged-temp and link guards, protected model/app stores/backups/Recall/update data, targeted registry-care journal and consistent selection numbering.
- Gaming 5.0: root one-click profile integration and interrupted-session priority restoration.
- Fixer 7.2: DISM before SFC, actual native output rather than guessed SFC repair verdicts, guarded shared temp cleanup, pending-update restart checks, checked DNS recovery, and update-cache repair that aborts on failed stops and reports partial/restart failures.
- Privacy 2.1: fail closed on unreadable registry snapshot state; verify registry/service/task undo and surface restore failures.
- Default AI/consumer debloat: modern Copilot AppX removal, checked Recall optional-feature disabling and Edge built-in model/API policies. Package and feature-state recovery; data-deletion limits remain explicit.
- Normalize short/long Windows Temp paths in shared cleanup, fixing skipped deletions for accounts using 8.3 aliases.
- Fix the Windows PowerShell signed/unsigned stay-awake flag error that prevented dashboard Windows repair and game-session mode from starting. Repair cleanup always releases the operation mutex and shows failed-command output.
- Decode SFC's redirected UTF-16LE output correctly instead of displaying embedded NUL characters; test its real read-only help/error output.
- 114 native Windows regression/boundary checks, including the real stay-awake API, repair-button/worker/native-process success/failure/restart paths, inventory buttons, fresh-package WPF tests and both folder layouts in CI.
- Recommend optimizerDuck in the dashboard and GitHub README, with an explicit coverage map. No Duck source or executable is bundled.
- Publish one complete portable ZIP with checksums and commit/CI provenance; keep shared modules with the tools. See [v3.0.0 release notes](docs/releases/v3.0.0.md).

## Toolkit v2.1.3 (2026-09-18)

Launcher fixes across the suite - the same silent-failure bug that broke the PC Cleaner start affected **eight more launchers** (all six DNS launchers, PC Privacy Guard, and both Gaming Optimizer launchers). The Encrypted DNS Manager not opening was this exact bug.

- Every launcher now uses the proven self-elevation pattern (`net session` check -> relaunch the launcher elevated -> run the script with a direct argument; no nested `-ArgumentList` quoting).
- Every launcher logs to `%LOCALAPPDATA%\Temp\<Tool>_launch.log`, verifies the elevated window actually started (sentinel file), and pauses with the exit code on failure instead of flashing away.
- `Validate_All.ps1` now rejects the broken `Start-Process -Verb RunAs -ArgumentList` pattern outright.

Tool scripts are unchanged; only launchers and validation were touched.

## Toolkit v2.1.1 (2026-09-18)

### PC Cleaner 1.0.2

- Launcher rewritten to the Corruption Fixer's proven self-elevation pattern (`net session` check -> relaunch elevated -> run the script in the same window). The nested `-ArgumentList` quoting unique to this launcher (and absent from every other suite launcher) is gone.
- The launcher logs to `%LOCALAPPDATA%\Temp\PCCleaner_launch.log` and pauses with the exit code on failure, so a startup failure is never invisible again.
- `Validate_All.ps1`: bat launchers must not contain backslash-escaped quotes (`\"`).

## Toolkit v2.1.1 (2026-09-18)

### PC Cleaner 1.0.1

- Registry scanning: every `Test-Path` check on registry-derived paths now tolerates access-denied locations (`-ErrorAction SilentlyContinue`), so one protected path can no longer abort the rest of a category scan (notably MuiCache).
- Same fix applied to the registry-restore directory check.

## Toolkit v2.1.0 (2026-09-18)

New tool: **PC Cleaner 1.0.0** — scan-first disk cleanup + registry care.

### PC Cleaner 1.0.0

- Scan-first UX: every category shows size, file count, risk tag, and a plain-English description before anything is deleted.
- One protected-path guard (`Assert-NotProtected`) blocks cookies, logins, history, bookmarks, sessions, app storage (IndexedDB/Local Storage), editor history, Extensions, and user folders (Desktop/Documents/Pictures/Videos/Music/OneDrive) in every delete path.
- Balanced profile (safe caches) + Strict profile (Windows Update cache, Prefetch, PWA caches, Recall snapshots, Windows.old).
- AI model stores (LM Studio/Ollama/Hugging Face/torch/whisper) are report-only with sizes — never deleted.
- `.bak`/`.old`/`.tmp`/`.orig` leftovers are removed only when a sibling original still exists; orphans are kept and reported.
- Registry Care: orphaned uninstall entries, dead Run/RunOnce values, stale App Paths, stale MuiCache entries, dead Startup shortcuts —每个 removal exports a `.reg` backup with a one-key restore (menu 7).
- `-Action SelfTest` asserts the guard and the backup-file rule; `-Action Scan` is a non-interactive read-only scan.

### Repository

- `Validate_All.ps1`: PC Cleaner checks added (protected-data markers; delete patterns for protected names are rejected).
- `START_TOOLKIT.bat`: PC Cleaner added to the menu.

## Toolkit v2.0.1 (2026-09-18)

PC Corruption Fixer **7.1.2** correctness pass after a full source review. Privacy Guard, Encrypted DNS and Gaming Optimizer are unchanged.

### PC Corruption Fixer 7.1.2

- SFC exit codes mapped correctly (1 = repaired, 2 = could not run). The old mapping reported exit 2 as "repaired" and treated a successful exit-1 repair as a failure.
- Post-DISM verification accepts a successful repair, runs with the sleep block held, and no longer treats "could not run" as a pass.
- Store re-register counts real successes via terminating errors; the result is no longer an unconditional PASS.
- Time-sync repair checks `w32tm /register`'s exit code and reports a missing W32Time service instead of claiming success.
- Orphan-service removal exports a registry backup (`%ProgramData%\WindowsPCToolkit\PCFixer\ServiceBackups`) before `sc delete` and refuses to delete when the backup fails.
- Startup-Viewer TEMP-path warning regex fixed (previously could never match).
- Orphan-service scan strips `\\?\` / `\??\` device-path prefixes correctly (was a no-op, risking false "orphan" candidates).
- AI privacy: snapshot failures abort cleanly before any change; partial restores are reported as partial.
- Restore-point enablement failures surface; DISM CheckHealth, component-cleanup, and event-scan summaries no longer overclaim.
- DNS snapshot covers all adapters (not only currently-Up ones); disk-space analyzer skips the multi-minute WinSxS walk.
- Removed six unused display helper functions.

### Repository

- README/release links now use the canonical `SenjuWoo` URLs; LICENSE holder updated.
- `dependabot.yml`: removed the invalid `powershell` ecosystem entry.
- `START_TOOLKIT.bat`: the validate branch pauses only for validation now.

## Toolkit v2.0.0 (2026-07-25)

Major safety rewrite of every tool. First release with the modular Gaming Optimizer, multi-profile Encrypted DNS Manager, Balanced/Strict Privacy Guard, and non-destructive Corruption Fixer defaults.

### Hotfix (same release train)

- Fixed a PowerShell parser failure in `PC_Fixer.ps1` (`${name}:` in an interpolated catch string).
- Corrected `Validate_All.ps1` so `Resolve-SuiteToolPath` is checked in `Optimizer.Core.psm1` (not Privacy Guard).
- PC Corruption Fixer version string: **7.1.1**.

## PC Corruption Fixer 7.1 / 7.1.1

- Replaced destructive AI/AppX/service/search removal with a documented, policy-only, exact-snapshot AI privacy manager.
- Fixed the reported CHKDSK path by making `Repair-Volume -Scan` primary.
- Added a deadlock-safe ProcessStartInfo-based CHKDSK fallback and correct handling for exit codes 0–3.
- Fixed elapsed-time reporting through fallback paths.
- Uses the actual Windows system drive instead of hard-coded `C:`.
- Removed network stack reset from Full Repair.
- Added non-destructive network/DNS health refresh to Full Repair.
- Explicit network reset now aborts when backup fails, checks native exit codes, records automatic-vs-static DNS state, and verifies DNS/DoH rollback.
- Recycle Bin cleanup is opt-in.
- Corrected Windows Update dashboard handling for Manual/trigger-start service state.
- Made Winsock the default explicit network repair; deeper TCP/IP reset is separately confirmed because it can remove custom adapter configuration.
- Rebuilt Windows Update repair without legacy mass DLL registration or Winsock reset.
- Update cache backups are timestamped and retained rather than overwritten.

## PC Privacy Guard 2.0

- Balanced mode now preserves the existing diagnostic-data level instead of forcing Required, avoiding silent conflicts with Insider enrollment; the explicit Required option warns before that tradeoff.
- Replaced legacy Bing/Cortana registry toggles with current Windows Search cloud, highlights, and location policy values plus reversible per-user cloud-search toggles.
- Made the DNS launcher work in both the bundled and clean GitHub layouts.
- Replaced fixed-default undo with exact registry/service/task snapshots.
- Added Balanced and Strict profiles.
- Balanced mode preserves `DiagTrack`, `wisvc`, Windows location, games, browsers and updates.
- Strict service/task disabling requires explicit confirmation.
- Browser undo no longer deletes entire policy keys.
- Removed automatic location-cache deletion and per-app permission sweeping.
- Corrected the IP-location explanation: DoH encrypts DNS; a VPN changes public IP.

## Encrypted DNS Manager 2.1

- Historical change introduced the incorrect Quad9 secondary IPv6 `2620:fe::fe:9`. The official Secure address is `2620:fe::9`; corrected in 3.0.1.
- Replaced the mixed Quad9/Mullvad adapter profile with one provider at a time.
- Added official Quad9 and all currently published Mullvad profiles.
- Every IPv4/IPv6 address is registered with its matching HTTPS DoH template.
- UDP fallback is disabled and automatic encrypted upgrade is enabled.
- Added mode-aware adapter DNS, DoH, and previous-provider snapshots with automatic rollback when application or verification fails.
- Added Quad9 live transport verification and honest Mullvad configuration verification.
- Added direct Quad9 and Mullvad AdBlock launchers.
- Corrected the DHCP launcher so it actually returns DNS to DHCP; exact snapshot restore now has a separate launcher.
- Made DHCP reset transactional with automatic rollback.
- Snapshot schema 3 records automatic/DHCP versus static DNS, preventing effective DHCP addresses from being restored as permanent static DNS.

## PC Gaming Optimizer 4.0

- Made cross-tool launchers resolve both bundled friendly folder names and the clean GitHub repository layout.
- Rebuilt around a shared module and exact snapshots.
- Removed forced global timers and BCD clock overrides.
- Removed blanket Nagle/QoS/MMCSS and NIC offload changes.
- Removed NTFS cache, disk timeout and storage LPM registry hacks.
- Removed unsafe GPU MSI writes and undocumented NVIDIA PowerMizer edits.
- Removed SysMain disabling, standby-list purges and permanent no-sleep power plan changes.
- Added opt-in cleanup for legacy v3.x overrides.
- Added read-only GPU, network, storage, memory, timer, MSI, display and PCVR audits.
- Added conservative Game Mode profile and process-scoped session booster.

## Earlier (v1.0.1)

Initial public monorepo packaging of Fixer 6.3, Optimizer 3.3, Privacy Guard 1.0.1, and Encrypted DNS 1.0.0.
