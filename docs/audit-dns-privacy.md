# DNS and Privacy Guard audit

Audit date: 2026-10-10. Scope: every file in `dns-encrypted-doh/` and `pc-privacy-guard/`, plus `Modules/Network.State.psm1`. Callers in `Toolkit.Worker.ps1`, `Modules/Toolkit.Core.psm1`, `pc-corruption-fixer/PC_Fixer.ps1`, gaming-tool path resolution, existing regression tests and `Validate_All.ps1` were traced. No new optimization or debloat features were added.

## Confirmed defects and corrections

| Defect | Mechanism and correction |
| --- | --- |
| Every fresh Privacy Guard undo was rejected | Snapshot creation omitted `Computer` and `User`, but restore required both. New verified snapshots contain computer, account and SID. Existing identity-less backups require explicit confirmation; foreign identities fail before writes. |
| Incorrect Quad9 IPv6 address | The provider used `2620:fe::fe:9`; the current official Secure service table and Windows 11 guide specify `2620:fe::9`. Corrected the provider data and added a regression assertion. The repository's previous validator incorrectly enforced the bad value; the whole-project integration corrects that validator. |
| Privacy backups could omit state that strict mode changed | Service and task inventory errors were suppressed. Inventory now fails closed, captures actual `Settings.Enabled`, records delayed automatic startup, and rejects transient service states that cannot be restored exactly. Snapshot JSON is read back before its pointer is published. |
| Strict privacy silently reported denied writes as successful | Service/task mutation used `SilentlyContinue`, then printed OK unconditionally. Errors now propagate, state is checked after successful writes, and only captured services/tasks are mutated. Saved unsupported service states fail restore preflight. |
| Registry writes lacked verification and unsupported types became strings | Exact writes now validate the requested type and check the resulting type/value. Array assignment preserves empty and single-element Binary/MultiString values through the read-back and JSON undo round trip. |
| DNS family errors could partially change an adapter | The shared setter changed IPv4 before discovering that requested IPv6 was unavailable. It now reads and validates both address-family objects before either mutation, and rejects empty adapter inventories. |
| Unsafe localized DoH fallback could destroy prior state | English-only `netsh` parsing returned null for unreadable flags, indistinguishable from an absent entry; deletion exit status was ignored. Supported typed Windows 11 DoH cmdlets now read/write the state, and unavailable APIs fail before profile writes. Existing entries are still updated in place. DoH writes and removals are read back. |
| DNS restore and DHCP reset could claim success incorrectly | Malformed static/automatic backup modes are rejected before encryption/adapter writes. DHCP reset now checks that both static server lists are empty and attempts the saved rollback on verification failure. Unreadable provider metadata aborts backup creation. Snapshots use unique filenames and UTF-8 pointers. |
| Standalone launchers broke on apostrophe paths or disabled Server service | Paths were injected into quoted PowerShell source; `net session` incorrectly stood in for administrator identity; the six-second sentinel could report a slow UAC response as failure. All seven scoped launchers now carry the exact path in an environment variable, disable inherited delayed expansion, check the Windows administrator role, wait for the elevated child and return its exit status. Privacy carries the original account SID through elevation and rejects alternate-account HKCU changes before state initialization. |

## Verification

`tests/Test_AuditDnsPrivacy.ps1` runs in Windows PowerShell 5.1. It uses an isolated HKCU test key and temporary JSON files. DNS, service and task mutations are intercepted before test execution. Coverage includes real typed registry round trips, fresh and legacy identity checks, inventory failures, strict mutation failures, per-family preflight, provider data, ignored DoH writes/deletes, malformed backups and DHCP rollback. The whole-project CI also runs the original regression suite and the friendly-folder layout.

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests\Test_AuditDnsPrivacy.ps1
```

The focused suite has **41 checks**, including quiet-default/debug-toggle, bounded failure-log, exact registry string-case and native foreign-SID entrypoint checks. Whole-project integration also checks the batch launchers using disposable native fixtures. These tests do not apply DNS/privacy profiles to the development PC.

## Version and logging

Encrypted DNS Manager is **2.2.1** (`DNS_Manager.ps1` header and version, `DNS_Encrypted_Manager.bat` title, DNS README). Privacy Guard is **2.1.1** (`PC_Privacy.ps1` header and version, `Run_As_Admin.bat` title, Privacy README). Shared network fixes are included with the toolkit patch version.

Detailed logging is quiet by default. Enable `-DebugLog` or `WINDOWS_PC_TOOLKIT_DEBUG=1` for startup version, resolved configuration and operation events. Errors are retained even when detailed logging is disabled:

- `%LOCALAPPDATA%\WindowsPCToolkit\Logs\DNS.log`
- `%LOCALAPPDATA%\WindowsPCToolkit\Logs\PrivacyGuard.log`

## Primary-source checks

- [Microsoft Set-DnsClientServerAddress](https://learn.microsoft.com/en-us/powershell/module/dnsclient/set-dnsclientserveraddress): per-family CIM input and reset-to-DHCP contract.
- [Microsoft Get-DnsClientDohServerAddress](https://learn.microsoft.com/en-us/powershell/module/dnsclient/get-dnsclientdohserveraddress): typed encryption configuration inventory.
- [Microsoft Set-DnsClientDohServerAddress](https://learn.microsoft.com/en-us/powershell/module/dnsclient/set-dnsclientdohserveraddress): existing-entry updates, automatic upgrade and UDP fallback semantics.
- [Quad9 services](https://docs.quad9.net/services/) and [Windows 11 encrypted DNS guide](https://docs.quad9.net/Setup_Guides/Windows/Windows_11_%28Encrypted%29/): Secure addresses and HTTPS template.
- [Quad9 protocol test](https://docs.quad9.net/FAQs/): `proto.on.quad9.net` TXT transport result.
- [AdGuard public DNS](https://adguard-dns.io/en/public-dns.html): matching default IPv4/IPv6 servers and HTTPS template.
- [Mullvad retirement announcement](https://mullvad.net/en/blog/shutting-down-our-public-encrypted-dns-servers-and-sponsoring-quad9-instead): migration before November 2, 2026; retired profiles remain excluded from new applies.

## Limits

No live DNS switch, service stop, scheduled-task change or production privacy policy was applied. Tests establish orchestration, read-back and rollback behavior; they do not certify every Windows edition, managed policy or provider/network combination. Quad9's live test checks the resolver path Windows actually used; it does not attest every independent adapter path. AdGuard still has no equivalent transport-attestation claim. Legacy snapshots can restore only the fields their original version recorded. Windows policy support can vary by edition and management settings.
