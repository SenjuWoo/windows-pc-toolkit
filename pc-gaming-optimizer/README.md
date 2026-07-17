# PC Gaming Optimizer v3.3

**Maximum Performance | Zero Bloat | Windows Update Safe | Sleep-safe | Kills Copilot & AI Parasites**

A comprehensive collection of PowerShell scripts to optimize Windows for gaming, GPU-intensive workloads, and AI image generation. Features an interactive GUI with system dashboard, category menus, and optimization status tracking.

## Quick Start

### Easiest Method (Double-Click)
1. Double-click **`Run_As_Admin.bat`** → Click "Yes" on the UAC prompt
2. Use the interactive menu to select optimizations
3. **Restart your PC** when done

### Manual Method
1. Right-click `PC_Optimizer.ps1` → **Run with PowerShell** (or "Run as Administrator")
2. Use the interactive menu
3. **Restart your PC** when done

## What's New in v3.3

- **Sleep-free long runs** — Optimize All / batch scripts block modern standby via `SetThreadExecutionState`; cursor + sleep policy restored on exit.
- **AC never-sleep** — `4_Optimize_Gaming.ps1` sets standby/hibernate/monitor timeout to **Never on AC** (battery policies left alone for laptops).
- **Game Booster stay-awake** — holds system + display awake for the whole session; releases cleanly in `finally`.
- **Encrypted DNS menu** — Network category can launch parent-folder `DNS_Set_Encrypted_DoH.ps1` (real DoH HTTPS templates for Quad9 + Mullvad AdBlock).
- **Hardened launcher** — `Run_As_Admin.bat` uses absolute `System32\WindowsPowerShell\v1.0\powershell.exe` (no PATH hijack).

## What's New in v3.2

- **NEW: `16_Display_Optimizer.ps1`** — comprehensive display check: detects current vs. maximum refresh rate per monitor with tier ratings (eSports/High/Standard/Low), Windows VRR (Variable Refresh Rate) status, G-SYNC/FreeSync capability detection, Resizable BAR guidance, and fullscreen optimization status. Flags misconfigurations with specific fix instructions.
- **NEW: Focus Assist for gaming** — `4_Optimize_Gaming.ps1` now configures Windows Focus Assist to suppress notifications during fullscreen gaming sessions (no more pop-ups mid-match).
- **NEW: ReBAR + driver version detection** — `3_Optimize_NVIDIA.ps1` now displays driver version, GPU ID, and Resizable BAR support status with BIOS setup instructions.
- **NEW: Display & GPU readiness in Benchmark** — `13_Benchmark.ps1` adds section [8/8] checking refresh rate, GPU driver version, ReBAR support, G-SYNC capability, Focus Assist status, and XMP/EXPO reminder.
- **Category menu reorganized** — New [7] Display & Monitor category; Benchmark moved to [8].
- **`9_Undo_All.ps1`** — adds Focus Assist undo.
- **`Run_All_Optimizations.ps1`** — includes `16_Display_Optimizer.ps1` in the full run.
- **DEEP Copilot & AI Purge** — `5_Kill_Windows_Parasites.ps1` now goes far beyond basic Copilot policy disabling. It kills the **CopilotSvc** background service, disables all **Copilot scheduled tasks**, removes the **Copilot AppX package**, blocks **Windows Recall** (the AI screenshot/timeline feature on Copilot+ PCs), disables **Windows AI features** (AI-powered Paint, Photos, data analysis), blocks **Microsoft 365 Copilot** integration, kills **AI-powered web search results**, and blocks **Chrome AI/genAI** in addition to Edge Copilot.
- **Edge Copilot Deep Block** — Now disables `CopilotPageContext`, `CopilotCDPPageContext`, `AIGenThemesEnabled`, and `AskCopilotEnabled` in addition to sidebar/spotlight.
- **Chrome AI Blocked** — New `GenAILocalFoundationalModelSettings` policy blocks Google AI features.
- **Copilot AppX Removed** — Finds and uninstalls `Microsoft.Copilot` and `Microsoft.WindowsAi` AppX packages for all users.
- **9_Undo_All.ps1** fully restores all new AI/Copilot/Recall settings.

## What's New in v3.1

- **NEW: Game Booster (`14_Game_Booster.ps1`)** - Pre-game session mode: purges RAM, flushes DNS, and **holds** the 0.5ms timer resolution for the whole gaming session (a normal script's timer request dies when the script exits - this one stays alive until you press a key).
- **NEW: Input Latency Optimizer (`15_Input_Latency.ps1`)** - Disables mouse acceleration for raw 1:1 aim (applied instantly, no reboot), kills the Sticky/Filter/Toggle Keys popups that steal focus mid-match, shortest keyboard repeat delay.
- **Fixed: HPET no longer forced** - v3.0 set `useplatformclock true`, which *hurts* frame times on modern CPUs. v3.1 removes it and keeps the fast default TSC clock source.
- **Fixed: HAGS registry value** - now sets `HwSchMode` (the value the Windows Settings toggle actually uses) in addition to `HwSchMode2`.
- **Fixed: Initial RTO** - v3.0 set 2000ms (slower loss recovery than the 1000ms default). v3.1 keeps the optimal default.
- **Fixed: RAM standby purge in Kill Parasites** - previous P/Invoke silently failed on 64-bit; now uses the same proven NtSetSystemInformation purge as Free RAM.
- **Removed: TCP Chimney / DCA tweaks** - those features were removed from Windows 10+; the commands did nothing.
- **Global timer resolution requests** - kernel flag so games' own high-resolution timer requests are honored even in borderless windowed / background (Win10 2004+/Win11).
- **Windows Copilot debloat** - disabled via policy (restored by Undo).
- **AMD + Intel shader caches** - cache cleaner now covers NVIDIA, AMD, Intel, DirectX.
- **Benchmark auto-comparison** - benchmark saves a JSON snapshot and automatically shows before/after deltas (RAM, CPU, ping, services, timer) vs the previous run.
- **Benchmark fixes** - ping measurement now works on Windows PowerShell 5.1; VRAM no longer caps at 4GB on modern GPUs.
- **System Restore point** - Optimize All now offers to create a restore point first.
- **Optimization status** - dashboard now also tracks Raw Mouse Input.

## What's New in v3.0

- **Windows Update Safe** - DoSvc (Delivery Optimization) is preserved, telemetry set to level 1 (Required) instead of 0. No more DISM 0x800f0915 errors.
- **Enhanced Interactive GUI** - Animated ASCII art header, system dashboard, optimization status indicators, category-based sub-menus.
- **System Dashboard** - Live CPU, GPU, RAM (with progress bar), power plan, and OS info.
- **Optimization Status Tracker** - Real-time green/grey indicators showing which optimizations are active.
- **New: SSD / Storage Optimization** - TRIM, NTFS tuning, disable storage power saving.
- **New: GPU MSI Mode** - Message Signaled Interrupts for lower GPU latency.
- **New: Timer Resolution** - 0.5ms system timer for smooth frame pacing, MMCSS tuning.
- **New: Benchmark & Snapshot** - Capture system metrics for before/after comparison.
- **Category Sub-Menus** - GPU & Graphics, Windows Gaming, Kill Bloat, Network, Storage & Memory, Timer & CPU.
- **Edge Browser De-bloat** - Disable Edge sidebar, spotlight, AI suggestions.

## Scripts Overview

| # | Script | Description | Admin |
|---|--------|-------------|:-----:|
| 1 | `1_Enable_HAGS.ps1` | Hardware-Accelerated GPU Scheduling | Yes |
| 2 | `2_Clear_Shader_Cache.ps1` | NVIDIA/DirectX/Windows shader caches | No |
| 3 | `3_Optimize_NVIDIA.ps1` | PowerMizer max perf, 10GB shader cache | Yes |
| 4 | `4_Optimize_Gaming.ps1` | Game Mode, power plan, DVR, Focus Assist, visual effects, background apps | Yes |
| 5 | `5_Kill_Windows_Parasites.ps1` | Telemetry, bloat, Copilot, Recall, AI, Cortana, ads (WU-safe) | Yes |
| 6 | `6_Network_Optimization.ps1` | TCP/IP, DNS, Nagle, adapter tuning, QoS | Yes |
| 7 | `7_Fix_Windows_Update.ps1` | Repair WU/DISM if previously broken | Yes |
| 8 | `8_Free_RAM.ps1` | Purge standby list for immediate memory | Yes |
| 9 | `9_Undo_All.ps1` | Restore all Windows defaults | Yes |
| 10 | `10_SSD_Optimization.ps1` | TRIM, NTFS tuning, storage power saving | Yes |
| 11 | `11_GPU_MSI_Mode.ps1` | Message Signaled Interrupts for GPUs | Yes |
| 12 | `12_Timer_Resolution.ps1` | Global timer requests, MMCSS, CPU scheduling | Yes |
| 13 | `13_Benchmark.ps1` | System snapshot, automatic before/after comparison, display/GPU readiness | No |
| 14 | `14_Game_Booster.ps1` | **NEW:** Pre-game boost, holds 0.5ms timer all session | Yes |
| 15 | `15_Input_Latency.ps1` | **NEW:** Raw mouse, no Sticky Keys popups, keyboard | Yes |
| 16 | `16_Display_Optimizer.ps1` | **NEW:** Refresh rate, VRR, G-SYNC, ReBAR detection + guidance | No |
| - | `PC_Optimizer.ps1` | **Interactive GUI launcher** | Yes |
| - | `Run_All_Optimizations.ps1` | Non-interactive runner (all scripts) | Yes |
| - | `Run_As_Admin.bat` | Double-click launcher with auto-elevation | - |

## Category Menu

The interactive GUI organizes scripts into categories:

1. **GPU & Graphics** - HAGS, NVIDIA, GPU MSI Mode, Shader Caches
2. **Windows Gaming & Input** - Game Mode, Power Plan, Visual Effects, Input Latency, Timer, Game Booster
3. **Kill Bloat & Parasites** - Telemetry, Cortana, Copilot, Ads, Tips, RAM cleanup
4. **Network** - TCP/IP, DNS, Nagle, Latency optimization
5. **Storage & Memory** - SSD TRIM, NTFS, Shader Cache, Free RAM
6. **Timer & CPU Scheduling** - Timer Resolution, MMCSS, Dynamic Tick, Game Booster
7. **Display & Monitor** - Refresh Rate, VRR, G-SYNC, ReBAR detection + guide
8. **Benchmark & System Info** - System snapshot, auto before/after comparison

Plus utility options:
- **[A] Optimize ALL** - One-click, with optional System Restore point
- **[G] Game Booster** - Run before gaming: RAM purge + DNS flush + holds 0.5ms timer
- **[F] Fix Windows Update** - Repair WU/DISM services
- **[U] Undo ALL** - Restore Windows defaults

## Windows Update Safety

**v3.0 intentionally preserves Windows Update functionality:**

- **DoSvc (Delivery Optimization)** is NOT disabled - it's required by Windows Update, Store, and DISM as the download service on Windows 10/11. Only P2P sharing is turned off (HTTP-only mode).
- **Telemetry policy** is set to level 1 (Required diagnostics only), NOT level 0. Level 0 breaks Windows Update health checks and DISM /RestoreHealth.
- **Application Experience scheduled tasks** are kept enabled - they're required for feature updates.
- **Xbox Live services** are kept enabled for Game Bar, PC Game Pass, and Xbox networking.

If Windows Update is still broken from a previous version, run the **[F] Fix Windows Update** option.

## What Each Script Does

### 1. Enable HAGS (`1_Enable_HAGS.ps1`)
- Enables Hardware-Accelerated GPU Scheduling (Windows 10 2004+/11)
- Reduces latency, improves GPU utilization
- Requires reboot

### 2. Clear Shader Cache (`2_Clear_Shader_Cache.ps1`)
- Clears stale shader caches (NVIDIA, AMD, Intel, DirectX, Windows)
- Fixes stuttering from corrupt/old cached shaders
- Safe to run anytime, no admin needed

### 3. Optimize NVIDIA (`3_Optimize_NVIDIA.ps1`)
- PowerMizer: Prefer Maximum Performance
- Shader cache limit: 10 GB (vs default 100 MB)
- **NEW: Driver version display** — shows installed NVIDIA driver
- **NEW: ReBAR detection** — checks GPU support + BIOS setup guide
- Works on any NVIDIA GPU

### 4. Windows Gaming (`4_Optimize_Gaming.ps1`)
- Power Plan: Ultimate Performance
- Game Mode: Enabled
- Game DVR/Bar recording: Disabled
- Background apps: Disabled
- SysMain (Superfetch): Disabled
- Power Throttling: Disabled
- Visual effects: Gaming balanced
- **NEW: Focus Assist** — suppresses notifications during fullscreen gaming

### 5. Kill Parasites (`5_Kill_Windows_Parasites.ps1`)
- Disables DiagTrack telemetry service
- P2P update sharing off (HTTP-only, service preserved)
- Kills Cortana, Bing web search, Widgets, Windows Copilot (deep removal)
- **NEW: Blocks Windows Recall** (AI screenshot/timeline on Copilot+ PCs)
- **NEW: Disables Windows AI features** (Paint, Photos, data analysis)
- **NEW: Blocks Microsoft 365 Copilot integration**
- **NEW: Removes Copilot AppX package** for all users
- **NEW: Kills CopilotSvc** background service + scheduled tasks
- **NEW: Blocks Chrome AI/genAI** + deep Edge Copilot blocking (page context, CDP, AI themes)
- Disables tips, ads, suggested content
- Clears RAM standby list (NtSetSystemInformation - same as RAMMap)
- Sets telemetry to level 1 (Required only - WU safe)

### 6. Network Optimization (`6_Network_Optimization.ps1`)
- TCP autotuning, congestion control (CTCP on Win10 / CUBIC kept on Win11), RSS
- Nagle's algorithm disabled (lower latency)
- Network throttling disabled
- DNS cache optimized
- NIC RSC disabled, checksum offload enabled
- QoS NLA bypass

### 7. Fix Windows Update (`7_Fix_Windows_Update.ps1`)
- Restores all WU services to factory defaults
- Re-enables Compatibility Appraiser tasks
- Removes registry policies blocking updates
- Optional: Reset WU cache, run DISM + SFC
- Triggers fresh update scan

### 8. Free RAM (`8_Free_RAM.ps1`)
- Purges standby list using NtSetSystemInformation API
- Same mechanism as Sysinternals RAMMap
- Instant memory boost before launching games

### 9. Undo All (`9_Undo_All.ps1`)
- Reverts ALL changes from any version of this optimizer
- Restores services, policies, gaming tweaks, input/mouse/accessibility,
  network, SSD, NVIDIA, timer, Copilot, power plan
- Requires reboot

### 10. SSD Optimization (`10_SSD_Optimization.ps1`)
- Enables TRIM on all SSDs
- Disables NTFS last-access timestamps
- Disables 8.3 short name generation
- Increases NTFS memory pools
- Disables storage power saving

### 11. GPU MSI Mode (`11_GPU_MSI_Mode.ps1`)
- Enables Message Signaled Interrupts on NVIDIA/AMD GPUs
- Reduces interrupt latency vs legacy IRQ lines
- Works with any discrete GPU

### 12. Timer Resolution (`12_Timer_Resolution.ps1`)
- Enables **global timer resolution requests** (persistent) so games' own
  high-resolution timer requests are honored system-wide, even in
  borderless windowed mode
- Disables dynamic tick for consistent timing
- Keeps the default TSC clock source (does NOT force HPET - that hurts frame times)
- MMCSS Games profile: GPU priority 8, High scheduling
- CPU priority separation: Foreground boost (0x26 - gaming standard)
- NOTE: a 0.5ms request only lasts while a process holds it - use Game Booster
  to hold it during a session

### 13. Benchmark (`13_Benchmark.ps1`)
- Captures system metrics: CPU, GPU, RAM, disk, network
- **NEW: Display checks** — refresh rate, GPU driver, ReBAR, G-SYNC, Focus Assist
- Checks optimization status (HAGS, Game Mode, DVR, etc.)
- Saves timestamped TXT report + JSON snapshot
- **Automatically compares** with your previous run and shows deltas
  (free RAM, CPU load, ping, services, processes, timer resolution)

### 14. Game Booster (`14_Game_Booster.ps1`) NEW
- Run right before launching a game
- Purges the RAM standby list (instant free memory)
- Flushes DNS (fresh game-server lookups)
- Requests 0.5ms timer resolution and **holds it** until you press a key -
  keep the window open (minimized is fine) while gaming
- Shows session length when you end it

### 15. Input Latency (`15_Input_Latency.ps1`) NEW
- Disables mouse acceleration (Enhanced Pointer Precision) for raw 1:1 aim -
  applied instantly via SystemParametersInfo, no reboot
- Disables Sticky Keys / Filter Keys / Toggle Keys hotkey popups
  (no more focus-stealing dialogs when you spam Shift mid-match)
- Keyboard repeat delay: shortest
- Does NOT touch your in-game sensitivity

### 16. Display Optimizer (`16_Display_Optimizer.ps1`) NEW
- Detects current refresh rate per monitor with gaming tier ratings
- Shows if you're at maximum refresh or leaving performance on the table
- Windows VRR (Variable Refresh Rate) status check
- G-SYNC/FreeSync capability detection with setup guide
- Resizable BAR (ReBAR) detection with BIOS enable instructions
- Fullscreen optimizations status check
- **Read-only** — no admin required, no settings changed
- Guides you through: Display Settings, NVIDIA Control Panel, BIOS

## Requirements

- Windows 10 (2004+) or Windows 11
- PowerShell 5.1+ (built-in)
- Administrator rights for most scripts
- NVIDIA GPU (for NVIDIA-specific scripts)

## Safety

- Only modifies well-documented registry keys and services
- **Optimize All offers to create a System Restore point** before changing anything
- No files deleted except shader caches (safe, auto-regenerated)
- No third-party tools installed, nothing downloaded from the internet
- Services are disabled/set to manual, not deleted
- All launchers run PowerShell with `-NoProfile` (no user profile scripts run elevated)
- `9_Undo_All.ps1` restores everything to factory defaults
- Windows Update functionality preserved by design

## For AI Workloads (SwarmUI/ComfyUI)

These optimizations also help GPU compute:
- HAGS reduces CPU-GPU scheduling overhead
- Max PowerMizer prevents GPU downclocking during inference
- Ultimate Performance power plan keeps CPU/PCIe at max speed
- GPU MSI mode reduces interrupt latency for compute
- RAM cleanup gives more memory to models
- SSD optimization speeds up model loading

## Customization

Edit any `.ps1` file to adjust settings. All paths use `$env:LOCALAPPDATA` and registry paths so they work on **any PC, any username**.

## License

Free to use, modify, and share.