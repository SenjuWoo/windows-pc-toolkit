# Windows PC Toolkit

Four admin PowerShell toolkits for **Windows 10/11**:

| Folder | App | What it does |
|--------|-----|----------------|
| [`dns-encrypted-doh/`](dns-encrypted-doh/) | **Encrypted DNS (DoH)** | Quad9 + Mullvad AdBlock over real **HTTPS** DoH templates |
| [`pc-gaming-optimizer/`](pc-gaming-optimizer/) | **PC Gaming Optimizer** | HAGS, NVIDIA, Game Mode, bloat kill, network, timer, game booster |
| [`pc-corruption-fixer/`](pc-corruption-fixer/) | **PC Corruption Fixer** | SFC/DISM, WU repair, network reset, health report, AI bloat removal |
| [`pc-privacy-guard/`](pc-privacy-guard/) | **PC Privacy Guard** | Location mask + tracker kill **without** breaking WU, games, or browsers |

All launchers elevate with an **absolute** `System32\WindowsPowerShell\v1.0\powershell.exe` path (no PATH hijack).

## Quick start

1. Clone or download this repo.
2. Open the folder for the tool you want.
3. Right-click / double-click the `Run_As_Admin.bat` (or DNS bat).
4. Accept UAC.
5. Restart when a tool says so.

```text
windows-pc-toolkit/
  dns-encrypted-doh/          DNS_Set_Quad9_Mullvad.bat
  pc-gaming-optimizer/        Run_As_Admin.bat
  pc-corruption-fixer/        Fix_Corruption.bat
  pc-privacy-guard/           Run_As_Admin.bat
```

## Safety principles (shared)

- **Windows Update safe** — Delivery Optimization (`DoSvc`) is kept; telemetry never forced to Level 0.
- **Games safe** — Xbox / Game Bar services left alone; camera/mic not killed by Privacy Guard.
- **Browsers safe** — policy-level telemetry/AI only; no proxy/homepage hijacks.
- **Undo paths** — Optimizer has Undo All; Privacy Guard has Undo; Fixer is repair-oriented.
- **Sleep-safe long runs** — Optimizer / Fixer block modern standby during long batches and release on exit.

## Encrypted DNS note

Plain DNS IPs alone are **not** encrypted. The DNS pack registers official DoH HTTPS templates:

| Provider | IP | DoH template |
|----------|-----|--------------|
| Quad9 | `9.9.9.9` | `https://dns.quad9.net/dns-query` |
| Mullvad AdBlock | `194.242.2.3` | `https://adblock.dns.mullvad.net/dns-query` |

Requires Windows 11 / Server 2022+ DoH client APIs for full HTTPS tunneling. Adapters are **auto-detected** (not hard-coded to `Ethernet`).

IP-based website geolocation is separate from Windows location APIs — use **Privacy Guard** for OS location + **Encrypted DNS / VPN** for the network layer.

## Requirements

- Windows 10 (2004+) or Windows 11
- PowerShell 5.1+ (built-in)
- Administrator rights for almost everything

## License

MIT — free to use, modify, and share. See [LICENSE](LICENSE).

## Disclaimer

These scripts change Windows services, registry policies, and network settings. Create a **System Restore point** first (tools offer this where it matters). You run them at your own risk. No warranty.
