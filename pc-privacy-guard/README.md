# PC Privacy Guard v2.1.1

A reversible Windows 10/11 privacy tool with two clearly separated profiles.

## Balanced profile, recommended

Reduces advertising and personalization, disables activity upload and feedback prompts, turns off selected browser metrics/studies, and disables Delivery Optimization peer-to-peer sharing. It preserves the existing diagnostic-data level so Insider enrollment and managed update/reporting features are not silently altered. It deliberately preserves:

- Windows Update, BITS, Delivery Optimization downloads, Store and Defender
- Windows Insider Service (`wisvc`)
- DiagTrack service and the current diagnostic-data level
- Windows location and per-app permissions
- Search suggestions and browser networking features
- Xbox/Game Bar, audio, graphics, camera and microphone services

## Strict profile

Adds Windows location policy, cloud search restrictions, DiagTrack/dmwappushservice disabling, and selected telemetry tasks. It requires a separate confirmation because those changes can remove useful diagnostics or features.

## Exact undo

Before any profile or individual action, the app records the exact registry values, service startup/state, and scheduled-task enabled state under:

`%ProgramData%\WindowsPCToolkit\PrivacyGuard\Snapshots`

Undo checks the snapshot's computer/user, restores those values and verifies registry types, service states and task flags. Restore failures stop the success message and show the actual error. It does not delete whole Edge, Chrome, Firefox, or Windows policy branches, so unrelated settings remain intact.

Version 2.1.1 records the identity fields that earlier snapshots omitted, verifies the backup before changes, and preserves delayed automatic service startup. Legacy backups with no recorded identity require explicit confirmation before restoring. Failed service/task inventory aborts the backup; denied strict-profile writes and failed read-back checks report failure.

## Encrypted DNS

Use the dashboard or root `dns-encrypted-doh\DNS_Manager.ps1` for Windows 11 DNS-over-HTTPS. DoH encrypts DNS lookups on the network path. It does not change your public IP; a VPN is the tool that changes the address websites see.

## Launch

Double-click `Run_As_Admin.bat`, accept UAC, and choose Balanced or individual controls. Reboot after Strict mode.

The launcher carries your original account SID through elevation. If UAC selects a different administrator account, Privacy Guard stops before initializing state or changing that account's HKCU settings.

In 2.1, unreadable registry state aborts snapshot creation rather than recording a missing value and risking an incorrect undo. Keep the full toolkit extracted together.

Errors are recorded in `%LOCALAPPDATA%\WindowsPCToolkit\Logs\PrivacyGuard.log`. Add `-DebugLog`, or set `WINDOWS_PC_TOOLKIT_DEBUG=1` before launching, to include startup version/configuration and operation events. Detailed logging is off by default.
