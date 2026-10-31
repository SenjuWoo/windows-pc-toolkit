# Blueprint review - 2026-10-31

An external "Architectural Audit and Modernization Blueprint" proposed a five-phase rewrite: modular `Compile.ps1` build, Pester/PSScriptAnalyzer gates, a runspace pool, transactional journal changes, per-interface `DohFlags`, `pktmon` DNS auditing, and a set of Windows 11 tweaks. This note records what was checked against the shipped 3.1.1 source (`018bc6414b02e4838f72074d560c569245d7d3ac`) and what was decided.

**Verdict: no code change applied.** Of the roughly two dozen recommendations, none describes a defect that reproduces in this repository. Most are already implemented, several describe code this toolkit does not contain, and the remainder are feature requests that need their own design. The blueprint reads as though it were written against a generic or imagined version of the toolkit, not this tree.

## Claims checked against the code

| Blueprint claim | Finding | Evidence |
| --- | --- | --- |
| Revert deletes or overwrites the undo journal, so a partial failure is unrecoverable | Already compensation-retaining: every step has `Status`, the journal is rewritten after each step, failures accumulate into `UndoNeedsAttention`, and the file is never deleted | `Modules/Toolkit.Core.psm1:636-726` |
| Journal paths can traverse outside the store | Path is canonicalized and must resolve under `Runs\` with a `.json` extension; unlinked-path and permission asserts run first | `Modules/Toolkit.Core.psm1:638-644` |
| Absent registry values are shown as "Off", misreporting OS defaults | Not applicable: the catalog is an apply-list, not a state display. Each write records `Before`/`After` including `Exists`, and undo restores the exact prior state, including removing a value that did not exist | `Modules/Toolkit.Core.psm1:125-150` |
| `Checkpoint-Computer` silently throttles on the 24-hour limit | The throttle is detected: the worker compares restore-point sequence numbers and fails with a cause instead of claiming success. No system-wide `SystemRestorePointCreationFrequency` change is made | `Toolkit.Worker.ps1:29-35`, `pc-corruption-fixer/PC_Fixer.ps1:1354-1364` |
| Setting `EnableAutoDoh` on Windows 10 gives a false sense of encryption | The DNS manager refuses the profile below build 22000 rather than writing an inert key; `EnableAutoDoh` is only read for a status display | `dns-encrypted-doh/DNS_Manager.ps1:153-154` |
| `Add-DnsClientDohServerAddress` throws when a template already exists | Already handled: read first, then `Set-` or `Add-`, followed by a read-back comparison | `dns-encrypted-doh/DNS_Manager.ps1:147-150` |
| Nothing proves encryption actually works | Template state, adapter DNS, live resolution and, for Quad9, a live DoH attestation through `proto.on.quad9.net`; other providers state that a transport attestation is unavailable | `dns-encrypted-doh/DNS_Manager.ps1:187-224` |
| Per-interface `DohFlags` must be written or Windows stays in plaintext | Not written here. The profile sets `AllowFallbackToUdp $false` with `AutoUpgrade $true` and passes the live attestation, so the claim is not demonstrated for this configuration. Not applied | `dns-encrypted-doh/DNS_Manager.ps1:147-198` |
| Long operations freeze the WPF message pump | Operations run in a separate PowerShell job (`Start-Job` -> `Toolkit.Worker.ps1`) and the UI polls progress; no runspace pool is needed | `Toolkit.ps1:101-121` |
| Mica/Acrylic rendering breaks on Windows 10, VMs and RDP | The dashboard uses no Mica, Acrylic, `WindowChrome` or DWM backdrop calls | grep over `*.ps1`/`*.xaml`: no matches |
| Global Fullscreen Optimizations disable hurts Windows 11 | No such tweak exists in the catalog | `Modules/Toolkit.Core.psm1:242-282` |
| MPO and IFEO priority tweaks need fixing | Neither feature exists in this tree | grep: no matches for `OverlayTestMode`, `PerfOptions` |
| `Set-Service` on `WaaSMedicSvc` throws and aborts the batch | The only `Set-Service` call is `W32Time`; no protected-service startup writes exist | `pc-corruption-fixer/PC_Fixer.ps1:2050` |
| Cleanup reports space it did not free | Bytes are added only when `Remove-ItemSafe` returns true; locked, denied, linked and protected paths return false and are logged. The dashboard temp action adds a file's length only after `Remove-Item` succeeds | `pc-cleaner/PC_Cleaner.ps1:340-360`, `407`, `426`; `Modules/Toolkit.Core.psm1:312-328` |
| Cleanup deletes temp files held by running apps | Files must be older than 7 days by both write and access time, and a failed removal is skipped rather than counted | `pc-cleaner/PC_Cleaner.ps1:406`, `471-482` |
| Classic context-menu CLSID tweak sets an empty default value incorrectly | That tweak is not in the toolkit | grep: no matches for `86ca1aa0` |
| A modular build with Pester and PSScriptAnalyzer is required | The repo already has `Validate_All.ps1` (46 PowerShell files, safety greps) and 629 fixture assertions in `tests/`. A rewrite is possible, not a defect | `Validate_All.ps1`, `tests/Test_All.ps1` |

## Valid observations, but features rather than fixes

These are real gaps in coverage, not defects in shipped behaviour. Each needs its own design, tests and release; none was applied here.

1. Accessibility: `Toolkit.xaml` has no `AutomationProperties.Name` on any control. Screen-reader navigation is weak.
2. DISM failures print a decimal HRESULT. A cause hint would help, but DISM already prints its own `Error: 0x...` line, and `PC_Fixer.ps1:772` deliberately refuses to map SFC exit codes because SFC's localized output is the verdict.
3. A read-only BitLocker/WinRE card before repair. No boot or BCD edits exist here, so exposure is indirect.
4. Capturing and restoring open File Explorer windows around the icon-cache rebuild, which currently stops Explorer.
5. Tiered AI controls (policy-only vs. component removal), a startup/persistence baseline diff, IFEO priority persistence, a three-state MPO control, and a classic context-menu toggle.

## External claims not verified

- CVE-2026-45585 ("YellowKey", a WinRE BitLocker bypass) appears in public reporting; the `autofstx.exe` detail was not confirmed, and the toolkit performs no boot or recovery-partition edits.
- The winutil and optimizerDuck PR numbers quoted in the blueprint were not checked and are not relied on here.
- "Windows 10 has no supported native DoH client" matches Microsoft's supported matrix and the module's own build gate.

## Decision

No code change. No described defect reproduces, the one applicable item (DISM hint text) duplicates output DISM already prints, and the architectural proposals would replace a verified design with a larger one that has no user-visible benefit. The backlog above is recorded so a future release can pick items deliberately rather than through a rewrite.
