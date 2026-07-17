# Encrypted DNS (DoH) — Quad9 + Mullvad AdBlock

Sets system DNS to **Quad9** (primary) + **Mullvad AdBlock** (secondary) with real **DNS-over-HTTPS** templates registered in Windows.

## Run

1. Double-click **`DNS_Set_Quad9_Mullvad.bat`** (UAC elevate).
2. To undo: **`DNS_Revert_DHCP.bat`**.

## Files

| File | Purpose |
|------|---------|
| `DNS_Set_Encrypted_DoH.ps1` | Registers DoH templates, sets DNS on all active adapters, `EnableAutoDoh=2` |
| `DNS_Set_Quad9_Mullvad.bat` | Elevating launcher |
| `DNS_Revert_DHCP.ps1` | DHCP restore + remove our DoH registrations |
| `DNS_Revert_DHCP.bat` | Elevating launcher for revert |

## Official HTTPS templates

- Quad9: `https://dns.quad9.net/dns-query` → `9.9.9.9` / `2620:fe::fe`
- Mullvad AdBlock: `https://adblock.dns.mullvad.net/dns-query` → `194.242.2.3` / `2a07:e340::3`

## Verify (elevated PowerShell)

```powershell
Get-DnsClientDohServerAddress
Get-DnsClientServerAddress -AddressFamily IPv4
```

Settings → Network → your adapter → DNS should show **DNS over HTTPS** on.
