# Windows PC Toolkit working rules

Read STATE.md and the current Git status/diff before editing. Source lives here; the sibling Windows-PC-Toolkit folder is a previous extracted release, not this repository. Preserve it and unrelated files/settings. Use authenticated gh for GitHub; never write credentials into project files.

Use built-in Windows PowerShell 5.1 with -NoProfile -STA for tests and WPF. Run Validate_All.ps1 and tests/Test_All.ps1; PowerShell 7 alone does not establish runtime compatibility. Tests may use only owned HKCU/Software/WindowsPCToolkitTests and TEMP fixtures for mutations. Read the interception setup before executing them. Never run live debloat, optimization, OneDrive uninstall/folder migration, repair or DNS changes as validation on the owner's configured PC.

OneDrive operations must preserve files, existing paths and custom local choices. Unverified paths are unknown, not safe. Check legacy and modern local aliases; re-read mutable external state at the action boundary. Never equate a bounded metadata scan with proof all cloud data is downloaded. Automatic registry-only folder restoration is retired; old requests must refuse without writes.

Keep semantic versions, changelog, user instructions and STATE.md synchronized. Add a focused regression for nontrivial logic. Reports are under %ProgramData%/WindowsPCToolkit and diagnostics under %LOCALAPPDATA%/WindowsPCToolkit/Logs; -DebugLog or WINDOWS_PC_TOOLKIT_DEBUG=1 enables detailed logging.

For releases: push first, record the exact SHA, require terminal-success checks for that SHA, and independently query Dependabot/code-scanning/secret-scanning alerts. Unavailable checks are unknown, not clean; unavailable Code Quality stays off. Build from the clean verified commit, compare payload files to its Git blobs, test the extracted artifact and freshly download/hash-check every uploaded asset. Preserve prior releases and journals. Report unperformed live/UI checks explicitly.
