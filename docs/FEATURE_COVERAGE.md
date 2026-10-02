# Feature coverage

[optimizerDuck](https://github.com/itsfatduck/optimizerDuck) is recommended for broader Windows customization. Categories checked October 1, 2026. This is overlap, not full tweak parity or performance equivalence.

| Area | Windows PC Toolkit |
| --- | --- |
| Gaming/performance | Game Mode, capture/mouse choices, temporary session priority, HAGS and benchmark snapshots. |
| Privacy | Advertising, tailored experiences, activity upload, suggestions and separate Balanced/Strict profiles. |
| GPU | Driver/MSI/display audits and manual HAGS; no automatic vendor power-state or undocumented GPU writes. |
| Power | Native settings, plan audit and temporary stay-awake; permanent plans, hibernation and USB policies preserved by default. |
| Bloatware/services | Default allowlisted consumer-AppX removal with a named confirmation and verified copies, startup/task disable and service health; no blanket service-disable profile. |
| Appearance | Animations, themes, extensions, taskbar alignment and Widgets button; a subset of Duck's catalogue. |
| AI | Modern Copilot removal, build-gated Recall feature disable/undo, Edge built-in model/API policies and advanced Windows/browser policies. Separate local AI stores preserved; deleted snapshots/browser models not restored. |
| Hardware | OS/build, CPU, RAM and services in WPF; GPU/storage/display details in console audits. |
| Startup/tasks | Run entries and third-party boot/logon tasks with saved-state undo; general task run/stop/delete in Windows Task Scheduler. |
| Cleanup | Aged Temp, official Delivery Optimization, scan-first cleaner and ReTrim; shaders for troubleshooting only. |
| Registry care | Typed backups and confirmed dead startup/MuiCache values, no broad sweep. |
| Repair/recovery | DISM → SFC, update-cache repair, diagnostics, dashboard undo and reports. |
| DNS | Quad9/AdGuard, per-family state, GUID restore, existing-entry update and rollback. |

Independent MIT implementation; no bundled Duck binary or copied GPL source. Download Duck from its own GitHub repository/releases.
