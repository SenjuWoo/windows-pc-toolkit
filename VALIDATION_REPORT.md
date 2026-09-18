# Validation Report

## Result

Static validation **passed** for Windows PC Toolkit **v2.0.1** (2026-09-18).

- PowerShell files checked: **29** (parser tokenization)
- Batch launchers: absolute `System32\WindowsPowerShell\v1.0\powershell.exe` paths
- Encrypted DNS: official HTTPS DoH templates, Quad9 secure IPv4/IPv6, `AutoUpgrade` / no UDP fallback
- Safety regression checks: Gaming Optimizer forbidden tweaks, Privacy Guard current policies, Fixer reversible AI markers, DNS DHCP/restore launchers

### Hotfix checks included

- `PC_Fixer.ps1` `${name}:` catch-string parse fix (7.1.1)
- `Validate_All.ps1` path-resolver check on `Optimizer.Core.psm1`
- Nested `_github_publish` exclusion no longer hides scripts when the clean repo is staged under that folder name
- PC Corruption Fixer 7.1.2 deep-review pass (SFC exit-code mapping, w32tm re-register verification, orphan-service registry backup, `\\?\` device-path strip, TEMP-path warning regex)

## Runtime note

Structural/static validation is **not** a full runtime confirmation of SFC, DISM, DnsClient, or registry policy application. After install, run `Validate_All.ps1` elevated on the target Windows machine and exercise tools carefully with restore points enabled.
