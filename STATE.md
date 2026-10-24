# Windows PC Toolkit handoff

## Goal and current milestone

Deliver a safe, usable native Windows toolkit for fresh installs and existing PCs, including a OneDrive local-folder preflight. Preserve the configured host, personal settings and previous releases.

3.1.1 source is implemented and locally verified, pending publication gates below. Started from clean main at 3a590b7d3a043d4fd6f7f93d11ea1a6200725148. There were no personal uncommitted edits to preserve. The change fixes Grok's 3.1.0 OneDrive implementation: uncertain paths and modern local aliases block the gate, uninstall rechecks external state, cloud metadata scans report incomplete coverage, and automatic registry-only folder restore is retired. The recovery button opens Microsoft's instructions. Already-local folders need no new OneDrive sign-in.

## Verified this session (2026-10-24)

- Existing gh keyring login works as SenjuWoo with repository ADMIN access. Global Git identity, gh credential helper, default main and auto upstream setup already persist across projects. Personal global Codex instructions are present; no global config, credentials, model choices or trust were changed.
- Shared Python on PATH is Python 3.14.9 at the runtime resolved by python: %LOCALAPPDATA%/Python/pythoncore-3.14-64/python.exe. The sandbox remaps LOCALAPPDATA and cannot launch the WindowsApps alias; use the resolved real interpreter path or authorized execution outside that sandbox. Do not install a duplicate Python. Git is 2.56.0.windows.3; gh is 2.103.1.
- Baseline 3.1.0 passed 614 native assertions again. The corrected source has 629 passing assertions across the same nine suites: OneDrive 42, base 117, Suite 51, Cleaner 57, DNS/privacy 99, repair/gaming 49, launchers 125, final gaming 24, final Fixer 65. A complete run passed before the final focused additions; changed suites passed again afterwards. Static validation passes on 46 PowerShell files.
- New regressions first failed on the original behavior: automatic restore to a missing destination, relative path accepted as safe, skipped cloud placeholders, stale uninstall status and contradictory cache status. They now pass. Kernel-only cloud flags are injected as boundary metadata, not represented as real provider proof.
- Actual WPF dashboard and OneDrive markup were rendered at 1200x860 and their pixels inspected. Read-only host status shows the five folders local and OneDrive absent; the profile path is anonymized in docs/images/onedrive.png. No host folder/policy mutation was performed.
- Published 3.1.0 exists at tag v3.1.0, commit fb98d610199a68a4a7fbd29dc4e9eb495e19bb79. CI run 40042883465 and Actions analysis 40042883423 are terminal-success on that SHA. All three alert queries returned zero. Its assets were downloaded again and match recorded hashes: ZIP 297448 bytes, SHA256 91e938ffee86db5bbc24c1fc18dd199fdb64973a3c2ac7cd60227ae938c4ed7e; provenance 3e716c7f0d7b01195a08a1971780ebaa45c26ebbd7f44cfbb2b563a36f0653ec; checksums 8f37464ffdb0f867c0bbb1fa09ea3c2794324b7c0492c0bf288048efe40bda1e.
- Correction to the old handoff: 66 of 67 3.1.0 payload files differ from raw Git blobs by CRLF line endings. All 67 match after newline normalization. Its claim of exact raw-byte equality was false. See .artifacts/resume-2026-10-24/published-3.1.0-byte-audit.json. The new package must match raw release-commit bytes.
- The preserved sibling Windows-PC-Toolkit contains 66 files, all matching 3.0.2 commit d8d263012bcc55e92c2081e89444f1532cd847d8 after newline normalization, with no unknown files. It was not changed. Older local backup locations mentioned by the former handoff are not present in this workspace and have not been reverified.

## First unfinished step

Review the final diff, push the release commit, record its exact SHA, and require all CI/analysis checks on it to reach successful terminal states. Query Dependabot, code-scanning and secret-scanning alerts again; unavailable Code Quality stays off. Build from that exact commit, compare every extracted raw Git blob, run the native tests on the extracted package, publish a forward 3.1.1 release, freshly download/hash-check all assets, and extract a separate versioned portable copy. Preserve the old 3.0.2 folder. Update this ledger with final SHA, CI links, hashes and paths.

Local build helper: .artifacts/resume-2026-10-24/release_bytes.py build <new-zip-path> <release-sha> --report <report-json>. It consumes git archive, excludes repository/test/validator/spec metadata and verifies all raw payload blobs. Package staging is _github_publish/release-3.1.1, which the validator explicitly excludes. Do not publish tests or private evidence logs.

## Commands, diagnostics and evidence

Run from this source folder with native System32 Windows PowerShell 5.1, -NoProfile and -STA:

- powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./Validate_All.ps1
- powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./tests/Test_All.ps1
- powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./Toolkit.ps1 -RenderPreview <png>
- Read-only CLI: powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ./Toolkit.Run.ps1 -Preview

Detailed logs: %LOCALAPPDATA%/WindowsPCToolkit/Logs; enable with -DebugLog or WINDOWS_PC_TOOLKIT_DEBUG=1. Reports/recovery journals: %ProgramData%/WindowsPCToolkit. Source validation logs and failed/passing regression evidence are in .artifacts/resume-2026-10-24 (ignored). Public coverage and limits: VALIDATION_REPORT.md, docs/ONEDRIVE_RECOVERY.md and docs/specs/2026-10-24-onedrive-review.md. Persistent project instructions: AGENTS.md. The parent WORKSPACE.md records source/release ownership and corrected Python discovery.

## Exact remaining limits

No live optimization, debloat, OneDrive uninstall, shell-folder migration, DNS changes, Windows repair, servicing, AppX removal/re-registration or FPS certification was performed. Interactive UAC and real cloud-provider outcomes remain untested. Fixture success is not live repair proof. A bounded scan cannot prove all cloud files were downloaded. Automatic registry-only folder restore is removed, not certified; old reports remain guarded against automatic undo.

The supplied shared ChatGPT URL returned only a page shell through retrieval, not its conversation text. The task uses the user's explicit OneDrive requirements and current Microsoft documentation instead; do not claim the history was read. Actions analysis covers Actions, not PowerShell. No new security scanner or paid feature was enabled.

## Last known good and preservation

Keep the separate Windows-PC-Toolkit 3.0.2 extracted release and existing reports/journals. The prior public releases remain available at https://github.com/SenjuWoo/windows-pc-toolkit/releases . The 3.1.0 ZIP and its matching public assets are retained in .artifacts/resume-2026-10-24/published-3.1.0 for comparison, but this review found the OneDrive defects documented above. Changelog: CHANGELOG.md.
