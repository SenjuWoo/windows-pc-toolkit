<p align="center">
  <img src="docs/images/logo.svg" width="72" height="72" alt="Windows PC Toolkit mark">
</p>

<h1 align="center">Windows PC Toolkit</h1>

<p align="center"><strong>Safe-by-default PowerShell tools for Windows 10/11.</strong></p>

<p align="center">
  Repair, cleanup, privacy, encrypted DNS, and gaming — rebuilt around exact snapshots,<br>
  rollback, and honest diagnostics. No tweak pile.
</p>

<p align="center">
  <a href="https://github.com/SenjuWoo/windows-pc-toolkit/actions/workflows/ci.yml"><img src="https://github.com/SenjuWoo/windows-pc-toolkit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-5b8a9a?labelColor=0e1418" alt="MIT License"></a>
  <a href="https://github.com/SenjuWoo/windows-pc-toolkit/releases/tag/v2.1.0"><img src="https://img.shields.io/badge/release-v2.1.0-7a9aaa?labelColor=0e1418" alt="v2.1.0"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a>
  ·
  <a href="#state-locations">Snapshots</a>
  ·
  <a href="#validate">Validate</a>
  ·
  <a href="#honest-status">Honest status</a>
  ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

This git tree has no application screenshot. The UI is `START_TOOLKIT.bat` and each tool's console menu.

| Folder | Version | Purpose |
| --- | ---: | --- |
| [`pc-corruption-fixer/`](pc-corruption-fixer/) | **7.1.2** | SFC/DISM, disk repair, Windows Update repair, diagnostics, reversible AI privacy policies |
| [`pc-privacy-guard/`](pc-privacy-guard/) | **2.0** | Balanced or Strict privacy profiles with exact undo |
| [`dns-encrypted-doh/`](dns-encrypted-doh/) | **2.1** | One-provider-at-a-time Windows DNS-over-HTTPS manager |
| [`pc-gaming-optimizer/`](pc-gaming-optimizer/) | **4.0** | Diagnostics + reversible supported gaming settings (no tweak pile) |
| [`pc-cleaner/`](pc-cleaner/) | **1.0.0** | Scan-first disk cleanup + registry care; never deletes user data |

## Why this rewrite exists

Earlier releases could "fix" things that made systems worse: Full Repair also reset networking, undo scripts guessed defaults, DNS mixed providers, and the gaming pack applied permanent timer/NIC/GPU registry hacks.

**v2.x toolkit design:**

- **JSON snapshots** under `%ProgramData%\WindowsPCToolkit` — restore what was actually there
- **Full Repair does not reset the network stack**
- **Network reset** aborts without a backup, preserves automatic vs static DNS, verifies DoH rollback
- **Encrypted DNS**: one provider profile, official HTTPS DoH templates, no plaintext UDP fallback
- **Gaming**: measurement-first; no permanent timer, Nagle, SysMain, MSI, PowerMizer, or standby-purge hacks
- **Privacy**: Balanced preserves WU/games/browsers/location; Strict is separate and confirmed
- **AI privacy**: policy-only and reversible — never uninstalls apps or disables Search/services
- **Cleaner**: scan-first with plainly labeled categories; never touches cookies, logins, history, app state, or AI model stores

## Quick start

1. Download a [release](https://github.com/SenjuWoo/windows-pc-toolkit/releases/tag/v2.1.0) or clone this repo.
2. Double-click **`START_TOOLKIT.bat`** for the launcher menu, **or** open a tool folder and run its `.bat`.
3. Accept UAC.
4. Prefer safe defaults; read each tool's README before Strict mode or network reset.

```text
windows-pc-toolkit/
  START_TOOLKIT.bat              # one menu for all tools + Validate_All
  Validate_All.ps1               # static safety/parser checks
  pc-corruption-fixer/           Fix_Corruption.bat
  pc-privacy-guard/              Run_As_Admin.bat
  dns-encrypted-doh/             DNS_Encrypted_Manager.bat
  pc-gaming-optimizer/           Run_As_Admin.bat
  pc-cleaner/                    Run_As_Admin.bat
```

All launchers elevate with an **absolute** `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` path (no PATH hijack).

## State locations

| Tool | Snapshots |
| --- | --- |
| Gaming Optimizer | `%ProgramData%\WindowsPCToolkit\GamingOptimizer\Snapshots` |
| Privacy Guard | `%ProgramData%\WindowsPCToolkit\PrivacyGuard\Snapshots` |
| Encrypted DNS | `%ProgramData%\WindowsPCToolkit\EncryptedDNS\Snapshots` |
| Corruption Fixer | `%ProgramData%\WindowsPCToolkit\PCFixer\NetworkSnapshots` · `AIFeatureSnapshots` |
| PC Cleaner | `%ProgramData%\WindowsPCToolkit\Cleaner\Logs` · `RegistryBackups` |

A failed apply rolls back from the snapshot it just wrote. Undo restores the recorded values, not guessed defaults.

## Validate

On Windows, run elevated:

```powershell
.\Validate_All.ps1
```

Uses Microsoft's PowerShell parser on every script, checks launcher paths and DoH templates, and rejects reintroduced unsafe optimization writes.

## Requirements

- Windows 10 (2004+) or Windows 11
- PowerShell 5.1+ (built-in)
- Administrator rights for almost everything
- Full DoH APIs: Windows 11 / Server 2022+ recommended for Encrypted DNS

## Honest status

Verified in this tree:

- latest GitHub release **v2.1.0**
- [`VALIDATION_REPORT.md`](VALIDATION_REPORT.md) — static validation **passed** (2026-09-18): 31 PowerShell files parsed, absolute launcher paths, official HTTPS DoH templates, Quad9 secure IPv4/IPv6, no UDP fallback, safety-regression checks
- CI (`.github/workflows/ci.yml`) — PowerShell parse + PSScriptAnalyzer, JSON, Python compile

Not claimed:

- a full runtime confirmation of SFC, DISM, DnsClient, or registry policy application on your machine
- that every Windows edition honours every AI/privacy policy
- a GUI screenshot (console menus only)

After install, run `Validate_All.ps1` elevated on the target Windows machine and exercise tools with restore points enabled.

## License

[MIT](LICENSE)

## Disclaimer

These scripts change Windows services, registry policies, and network settings. Create a **System Restore point** first (tools offer this where it matters). You run them at your own risk. No warranty.

See [CHANGELOG.md](CHANGELOG.md) for the full rebuild notes.
