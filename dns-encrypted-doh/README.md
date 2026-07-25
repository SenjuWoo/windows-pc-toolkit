# Encrypted DNS Manager v2.1

This folder configures Windows 11 DNS-over-HTTPS using official provider HTTPS templates.

## Why v2.1 exists

The old script mixed Quad9 and Mullvad on the same adapter. That split queries between providers with different filtering policies and made verification muddy. v2.1 chooses **one provider profile at a time**, registers a DoH template for every selected IPv4/IPv6 address, enables automatic encrypted upgrade, disables UDP fallback, and verifies the result.

## Launchers

- `DNS_Encrypted_Manager.bat`: opens the provider menu
- `DNS_Set_Quad9_Mullvad.bat`: opens the provider menu, retained for compatibility
- `DNS_Set_Quad9.bat`: applies Quad9 Secure
- `DNS_Set_Mullvad_AdBlock.bat`: applies Mullvad AdBlock
- `DNS_Revert_DHCP.bat`: returns active adapters to automatic/DHCP DNS
- `DNS_Restore_Previous.bat`: restores the exact previous snapshot

The DHCP reset is transactional: if it fails, the pre-reset state is restored automatically. New snapshots record whether each adapter used automatic/DHCP DNS or explicit static DNS, so restore does not accidentally turn DHCP-provided addresses into permanent static addresses.

Snapshots are stored in `%ProgramData%\WindowsPCToolkit\EncryptedDNS\Snapshots`. Legacy v2.0 snapshots remain readable, but only v2.1 schema-3 snapshots contain DNS-mode metadata.

## Verification

The tool checks that each IP has the expected `https://.../dns-query` template, `AutoUpgrade` is enabled, and plaintext UDP fallback is disabled. Quad9 additionally supports a live TXT test that reports `doh` when the active transport is HTTPS.

Mullvad profiles are configuration-verified because they do not publish the same Windows TXT protocol test. The tool does not falsely report a live transport result it cannot prove.

## Important

An IP address alone is not encrypted DNS. Windows must have the matching DoH HTTPS template and must not fall back to UDP port 53. Encrypted DNS hides DNS lookups from the local network path; it does not replace a VPN or change the public IP address.
