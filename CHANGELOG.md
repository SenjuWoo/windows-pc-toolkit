# Changelog

## Toolkit v2.0.0 (2026-07-25)

Major safety rewrite of every tool. First release with the modular Gaming Optimizer, multi-profile Encrypted DNS Manager, Balanced/Strict Privacy Guard, and non-destructive Corruption Fixer defaults.

### Hotfix (same release train)

- Fixed a PowerShell parser failure in `PC_Fixer.ps1` (`${name}:` in an interpolated catch string).
- Corrected `Validate_All.ps1` so `Resolve-SuiteToolPath` is checked in `Optimizer.Core.psm1` (not Privacy Guard).
- PC Corruption Fixer version string: **7.1.1**.

## PC Corruption Fixer 7.1 / 7.1.1

- Replaced destructive AI/AppX/service/search removal with a documented, policy-only, exact-snapshot AI privacy manager.
- Fixed the reported CHKDSK path by making `Repair-Volume -Scan` primary.
- Added a deadlock-safe ProcessStartInfo-based CHKDSK fallback and correct handling for exit codes 0–3.
- Fixed elapsed-time reporting through fallback paths.
- Uses the actual Windows system drive instead of hard-coded `C:`.
- Removed network stack reset from Full Repair.
- Added non-destructive network/DNS health refresh to Full Repair.
- Explicit network reset now aborts when backup fails, checks native exit codes, records automatic-vs-static DNS state, and verifies DNS/DoH rollback.
- Recycle Bin cleanup is opt-in.
- Corrected Windows Update dashboard handling for Manual/trigger-start service state.
- Made Winsock the default explicit network repair; deeper TCP/IP reset is separately confirmed because it can remove custom adapter configuration.
- Rebuilt Windows Update repair without legacy mass DLL registration or Winsock reset.
- Update cache backups are timestamped and retained rather than overwritten.

## PC Privacy Guard 2.0

- Balanced mode now preserves the existing diagnostic-data level instead of forcing Required, avoiding silent conflicts with Insider enrollment; the explicit Required option warns before that tradeoff.
- Replaced legacy Bing/Cortana registry toggles with current Windows Search cloud, highlights, and location policy values plus reversible per-user cloud-search toggles.
- Made the DNS launcher work in both the bundled and clean GitHub layouts.
- Replaced fixed-default undo with exact registry/service/task snapshots.
- Added Balanced and Strict profiles.
- Balanced mode preserves `DiagTrack`, `wisvc`, Windows location, games, browsers and updates.
- Strict service/task disabling requires explicit confirmation.
- Browser undo no longer deletes entire policy keys.
- Removed automatic location-cache deletion and per-app permission sweeping.
- Corrected the IP-location explanation: DoH encrypts DNS; a VPN changes public IP.

## Encrypted DNS Manager 2.1

- Corrected Quad9 secondary IPv6 to the official secure-profile address `2620:fe::fe:9`; the previous value belonged to a different Quad9 service family.
- Replaced the mixed Quad9/Mullvad adapter profile with one provider at a time.
- Added official Quad9 and all currently published Mullvad profiles.
- Every IPv4/IPv6 address is registered with its matching HTTPS DoH template.
- UDP fallback is disabled and automatic encrypted upgrade is enabled.
- Added mode-aware adapter DNS, DoH, and previous-provider snapshots with automatic rollback when application or verification fails.
- Added Quad9 live transport verification and honest Mullvad configuration verification.
- Added direct Quad9 and Mullvad AdBlock launchers.
- Corrected the DHCP launcher so it actually returns DNS to DHCP; exact snapshot restore now has a separate launcher.
- Made DHCP reset transactional with automatic rollback.
- Snapshot schema 3 records automatic/DHCP versus static DNS, preventing effective DHCP addresses from being restored as permanent static DNS.

## PC Gaming Optimizer 4.0

- Made cross-tool launchers resolve both bundled friendly folder names and the clean GitHub repository layout.
- Rebuilt around a shared module and exact snapshots.
- Removed forced global timers and BCD clock overrides.
- Removed blanket Nagle/QoS/MMCSS and NIC offload changes.
- Removed NTFS cache, disk timeout and storage LPM registry hacks.
- Removed unsafe GPU MSI writes and undocumented NVIDIA PowerMizer edits.
- Removed SysMain disabling, standby-list purges and permanent no-sleep power plan changes.
- Added opt-in cleanup for legacy v3.x overrides.
- Added read-only GPU, network, storage, memory, timer, MSI, display and PCVR audits.
- Added conservative Game Mode profile and process-scoped session booster.

## Earlier (v1.0.1)

Initial public monorepo packaging of Fixer 6.3, Optimizer 3.3, Privacy Guard 1.0.1, and Encrypted DNS 1.0.0.
