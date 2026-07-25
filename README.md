# Windows PC Toolkit

Safe-by-default PowerShell tools for **Windows 10/11**: repair, privacy, encrypted DNS, and gaming — rebuilt around exact snapshots, rollback, and honest diagnostics.

| Folder | Version | Purpose |
|--------|--------:|---------|
| [`pc-corruption-fixer/`](pc-corruption-fixer/) | **7.1.1** | SFC/DISM, disk repair, Windows Update repair, diagnostics, reversible AI privacy policies |
| [`pc-privacy-guard/`](pc-privacy-guard/) | **2.0** | Balanced or Strict privacy profiles with exact undo |
| [`dns-encrypted-doh/`](dns-encrypted-doh/) | **2.1** | One-provider-at-a-time Windows DNS-over-HTTPS manager |
| [`pc-gaming-optimizer/`](pc-gaming-optimizer/) | **4.0** | Diagnostics + reversible supported gaming settings (no tweak pile) |

## Why this rewrite exists

Earlier releases could “fix” things that made systems worse: Full Repair also reset networking, undo scripts guessed defaults, DNS mixed providers, and the gaming pack applied permanent timer/NIC/GPU registry hacks.

**v2.x toolkit design:**

- **JSON snapshots** under `%ProgramData%\WindowsPCToolkit` — restore what was actually there
- **Full Repair does not reset the network stack**
- **Network reset** aborts without a backup, preserves automatic vs static DNS, verifies DoH rollback
- **Encrypted DNS**: one provider profile, official HTTPS DoH templates, no plaintext UDP fallback
- **Gaming**: measurement-first; no permanent timer, Nagle, SysMain, MSI, PowerMizer, or standby-purge hacks
- **Privacy**: Balanced preserves WU/games/browsers/location; Strict is separate and confirmed
- **AI privacy**: policy-only and reversible — never uninstalls apps or disables Search/services

## Quick start

1. Download a [release](https://github.com/ShugokiFable/windows-pc-toolkit/releases) or clone this repo.
2. Double-click **`START_TOOLKIT.bat`** for the launcher menu, **or** open a tool folder and run its `.bat`.
3. Accept UAC.
4. Prefer safe defaults; read each tool’s README before Strict mode or network reset.

```text
windows-pc-toolkit/
  START_TOOLKIT.bat              # one menu for all tools + Validate_All
  Validate_All.ps1               # static safety/parser checks
  pc-corruption-fixer/           Fix_Corruption.bat
  pc-privacy-guard/              Run_As_Admin.bat
  dns-encrypted-doh/             DNS_Encrypted_Manager.bat
  pc-gaming-optimizer/           Run_As_Admin.bat
```

All launchers elevate with an **absolute**  
`%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` path (no PATH hijack).

## State locations

| Tool | Snapshots |
|------|-----------|
| Gaming Optimizer | `%ProgramData%\WindowsPCToolkit\GamingOptimizer\Snapshots` |
| Privacy Guard | `%ProgramData%\WindowsPCToolkit\PrivacyGuard\Snapshots` |
| Encrypted DNS | `%ProgramData%\WindowsPCToolkit\EncryptedDNS\Snapshots` |
| Corruption Fixer | `%ProgramData%\WindowsPCToolkit\PCFixer\NetworkSnapshots` · `AIFeatureSnapshots` |

## Validate

On Windows, run elevated:

```powershell
.\Validate_All.ps1
```

Uses Microsoft’s PowerShell parser on every script, checks launcher paths and DoH templates, and rejects reintroduced unsafe optimization writes.

## Requirements

- Windows 10 (2004+) or Windows 11  
- PowerShell 5.1+ (built-in)  
- Administrator rights for almost everything  
- Full DoH APIs: Windows 11 / Server 2022+ recommended for Encrypted DNS

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

These scripts change Windows services, registry policies, and network settings. Create a **System Restore point** first (tools offer this where it matters). You run them at your own risk. No warranty.

See [CHANGELOG.md](CHANGELOG.md) for the full rebuild notes.
