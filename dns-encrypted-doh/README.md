# Encrypted DNS Manager 2.2

Windows 11 DNS-over-HTTPS using one provider per physical adapter. Use the [dashboard](../README.md) or `DNS_Encrypted_Manager.bat`. Extract the full toolkit, including `Modules\Network.State.psm1`.

| Provider | IPv4 | HTTPS template |
| --- | --- | --- |
| Quad9 Secure | `9.9.9.9`, `149.112.112.112` | `https://dns.quad9.net/dns-query` |
| AdGuard DNS | `94.140.14.14`, `94.140.15.15` | `https://dns.adguard-dns.com/dns-query` |

Matching IPv6 servers are registered; adapters receive them only with usable IPv6 and a default IPv6 route. Quad9 is the recommended ongoing profile. [Quad9](https://docs.quad9.net/services/), [AdGuard](https://adguard-dns.io/en/public-dns.html).

**Mullvad public DNS retires November 2, 2026.** New Mullvad applies and menu choices are removed now; backup restore remains available. [Official announcement](https://mullvad.net/en/blog/2026/9/3/shutting-down-our-public-encrypted-dns-servers-and-sponsoring-quad9-instead).

## Correctness

- Update existing DoH entries in place; automatic upgrade on, UDP fallback off.
- Save affected DoH entries and IPv4/IPv6 static/automatic modes before writing.
- Select physical adapters with default routes or an explicit physical index; exclude VPN/virtual adapters.
- Restore by GUID even if indexes changed. Missing original adapters abort before DNS changes.
- Verify addresses, flags, templates and resolution. Quad9 also requires its live TXT result to report `doh`; unavailable tests fail.
- Attempt rollback after failed apply and report rollback failures.
- Automatic DNS preserves global DoH entries used by other adapters.

AdGuard checks validate configuration/resolution without claiming Quad9's live attestation. DoH does not change public IP or replace a VPN.

Snapshots: `%ProgramData%\WindowsPCToolkit\EncryptedDNS\Snapshots`. Schema 4 tracks affected encryption entries. Schema 2/3 backups with stable adapter identity remain readable; only backups that recorded mode can restore automatic/static exactly.

```powershell
.\DNS_Manager.ps1 -Action Quad9 -InterfaceIndex 12
.\DNS_Manager.ps1 -Action AdGuard -InterfaceIndex 12
.\DNS_Manager.ps1 -Action Verify -InterfaceIndex 12
.\DNS_Manager.ps1 -Action Restore
.\DNS_Manager.ps1 -Action DHCP -InterfaceIndex 12
```

Replace `12` with your physical adapter index. Historical `DNS_Set_Quad9_Mullvad.bat` and `DNS_Set_Mullvad_AdBlock.bat` open the supported-provider menu. They do not silently change your provider.
