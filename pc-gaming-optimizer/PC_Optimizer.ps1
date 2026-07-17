<#
.SYNOPSIS
    Modern PC Gaming Optimizer v3.3 with enhanced visuals and category menus.
.DESCRIPTION
    Interactive launcher with system dashboard, optimization status tracking,
    category-based sub-menus, benchmark tools, and one-click optimization.
    v3.3: sleep-prevention during long runs, cursor restore on exit, safer
    child-script invocation, encrypted-DNS menu hook, hardened launcher path.
.NOTES
    Run as Administrator. Prefer Run_As_Admin.bat (auto-elevates).
#>

#Requires -RunAsAdministrator

# ---------------------------------------------------------
# CONSOLE SETUP
# ---------------------------------------------------------
$Host.UI.RawUI.WindowTitle = "PC Gaming Optimizer v3.3"
$script:PrevCursorSize = 25
try { $script:PrevCursorSize = $Host.UI.RawUI.CursorSize } catch { }
try { $Host.UI.CursorSize = 0 } catch { }
Clear-Host

$scriptDir = $PSScriptRoot
$ErrorActionPreference = 'Continue'

# Keep the PC awake during long optimization batches (SFC-like waits, many scripts).
# ES_CONTINUOUS | ES_SYSTEM_REQUIRED — restored in finally on exit.
try {
    $awakeSrc = @'
using System;
using System.Runtime.InteropServices;
public static class StayAwake {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
    public const uint ES_CONTINUOUS = 0x80000000;
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
    public const uint ES_AWAYMODE_REQUIRED = 0x00000040;
    public static void PreventSleep() {
        SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
    }
    public static void AllowSleep() {
        SetThreadExecutionState(ES_CONTINUOUS);
    }
}
'@
    if (-not ('StayAwake' -as [type])) { Add-Type -TypeDefinition $awakeSrc -ErrorAction Stop }
    [StayAwake]::PreventSleep()
} catch { }

# ---------------------------------------------------------
# VISUAL CHARACTERS (defined as variables for reliability)
# ---------------------------------------------------------
$CH = [string][char]0x2500  # ─  light horizontal

$DH = [string][char]0x2550  # ═  double horizontal
$DV = [string][char]0x2551  # ║  double vertical
$DTL = [string][char]0x2554 # ╔  double top-left
$DTR = [string][char]0x2557 # ╗  double top-right
$DBL = [string][char]0x255A # ╚  double bottom-left
$DBR = [string][char]0x255D # ╝  double bottom-right

$BLK = [string][char]0x2588 # █  full block
$LIT = [string][char]0x2591 # ░  light shade
$BULL = [string][char]0x25CB # ○  white circle
$FULL = [string][char]0x25CF # ●  black circle

$HLINE = $DH * 48
$SLINE = $CH * 60

# ---------------------------------------------------------
# UTILITY FUNCTIONS
# ---------------------------------------------------------
function Write-Blank($n = 1) { for ($i = 0; $i -lt $n; $i++) { Write-Host "" } }

function Write-Separator {
    param($char = $CH, $color = "DarkGray")
    $w = [Math]::Max(1, $Host.UI.RawUI.WindowSize.Width - 4)
    Write-Host "  $($char * $w)" -ForegroundColor $color
}

function Show-ProgressBar {
    param($Value, $Max, $Width = 30, $Label = "", $Color = "Green")
    $pct = if ($Max -gt 0) { [Math]::Min(100, [int](($Value / $Max) * 100)) } else { 0 }
    $filled = [int]($Width * $pct / 100)
    $empty = $Width - $filled
    $barColor = if ($pct -gt 85) { "Red" } elseif ($pct -gt 65) { "Yellow" } else { $Color }
    if ($Label) {
        Write-Host "    $Label " -ForegroundColor Gray -NoNewline
    }
    Write-Host "[" -ForegroundColor DarkGray -NoNewline
    Write-Host ("$BLK" * $filled) -ForegroundColor $barColor -NoNewline
    Write-Host ("$LIT" * $empty) -ForegroundColor DarkGray -NoNewline
    Write-Host "] " -ForegroundColor DarkGray -NoNewline
    Write-Host "$pct%" -ForegroundColor $barColor
}

function Show-StatusDot {
    param($Enabled, $Label)
    if ($Enabled) {
        Write-Host "    $FULL $Label" -ForegroundColor Green
    } else {
        Write-Host "    $BULL $Label" -ForegroundColor DarkGray
    }
}

function Test-RegistryValue {
    param($Path, $Name, $Expected)
    try {
        $val = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
        if ($null -eq $val) { return $null }
        return ($val -eq $Expected)
    }
    catch { return $false }
}

function Get-ActiveStatus {
    $diagVal = $false
    try { $s = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack" -Name "Start" -EA SilentlyContinue).Start; $diagVal = ($s -eq 4) } catch {}
    $widgVal = $false
    try { $s = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -EA SilentlyContinue).AllowNewsAndInterests; $widgVal = ($s -eq 0) } catch {}
    # HAGS: HwSchMode is the documented toggle; HwSchMode2 exists on newer builds
    $hagsVal = $false
    try {
        $g = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -EA SilentlyContinue
        $hagsVal = ($g.HwSchMode -eq 2) -or ($g.HwSchMode2 -eq 2)
    } catch {}
    $mouseVal = $false
    try { $m = (Get-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -EA SilentlyContinue).MouseSpeed; $mouseVal = ($m -eq "0") } catch {}
    $script:optStatus = @{
        HAGS       = $hagsVal
        GameMode   = Test-RegistryValue "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 1
        GameDVROff = Test-RegistryValue "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
        PowerThrottle = Test-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1
        DiagTrack  = $diagVal
        Widgets    = $widgVal
        RawMouse   = $mouseVal
    }
}

function Show-Header {
    Clear-Host
    Write-Blank
    Write-Host "  $DTL$HLINE$DTR" -ForegroundColor DarkCyan
    Write-Host "  $DV                                                $DV" -ForegroundColor DarkCyan
    Write-Host "  $DV    ____   ____   ____   _    ____  ____  _  __ $DV" -ForegroundColor Cyan
    Write-Host "  $DV   / ___) / __ \ / __ \ / \  / ___)(_  _)( \(  ) $DV" -ForegroundColor Cyan
    Write-Host "  $DV  (___  \(  __/(  __//   \  \__ \   )(   /  )(   $DV" -ForegroundColor White
    Write-Host "  $DV  (____/  \___) \___)\_/\_\/(____/  (__) (_/\_\/ $DV" -ForegroundColor Yellow
    Write-Host "  $DV                                                $DV" -ForegroundColor DarkCyan
    Write-Host "  $DV        PC GAMING OPTIMIZER  v3.3               $DV" -ForegroundColor Yellow
    Write-Host "  $DV   * MAXIMUM PERFORMANCE  |  ZERO BLOAT *       $DV" -ForegroundColor Yellow
    Write-Host "  $DV   Windows Update Safe  |  Sleep-safe long runs $DV" -ForegroundColor Green
    Write-Host "  $DV                                                $DV" -ForegroundColor DarkCyan
    Write-Host "  $DBL$HLINE$DBR" -ForegroundColor DarkCyan
    Write-Blank
}

function Show-Dashboard {
    Write-Host "  SYSTEM DASHBOARD" -ForegroundColor White
    Write-Separator $CH

    # CPU
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $cpuName = $cpu.Name -replace '\s+', ' '
        if ($cpuName.Length -gt 50) { $cpuName = $cpuName.Substring(0, 47) + "..." }
        Write-Host "  CPU  " -ForegroundColor Gray -NoNewline
        Write-Host $cpuName -ForegroundColor White
        Write-Host "       " -NoNewline
        $cores = $cpu.NumberOfCores
        $threads = $cpu.NumberOfLogicalProcessors
        Write-Host "$cores cores / $threads threads" -ForegroundColor DarkGray -NoNewline
        Write-Host "  |  Load: " -ForegroundColor DarkGray -NoNewline
        $loadColor = if($cpu.LoadPercentage -lt 50){"Green"}elseif($cpu.LoadPercentage -lt 80){"Yellow"}else{"Red"}
        Write-Host "$($cpu.LoadPercentage)%" -ForegroundColor $loadColor
    } catch {}

    # GPU
    try {
        # AdapterRAM is capped at 4GB (32-bit) - prefer qwMemorySize from the driver key
        $vramRegGB = 0
        try {
            $qw = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue | ForEach-Object {
                $_.GetValue("HardwareInformation.qwMemorySize")
            } | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
            if ($qw) { $vramRegGB = [Math]::Round($qw / 1GB, 1) }
        } catch {}
        Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch "Microsoft Basic|Remote Desktop" } | Select-Object -First 1 | ForEach-Object {
            $gpuName = $_.Name -replace '\s+', ' '
            if ($gpuName.Length -gt 50) { $gpuName = $gpuName.Substring(0, 47) + "..." }
            Write-Host "  GPU  " -ForegroundColor Gray -NoNewline
            Write-Host $gpuName -ForegroundColor White
            $vramGB = if ($vramRegGB -gt 0) { $vramRegGB } else { [Math]::Round($_.AdapterRAM / 1GB, 1) }
            Write-Host "       VRAM: ${vramGB} GB" -ForegroundColor DarkGray
        }
    } catch {}

    # RAM
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeGB = [Math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $usedGB = $totalGB - $freeGB
        Write-Host "  RAM  " -ForegroundColor Gray -NoNewline
        Write-Host "${totalGB} GB total" -ForegroundColor White -NoNewline
        Write-Host "  |  " -ForegroundColor DarkGray -NoNewline
        Write-Host "${freeGB} GB free" -ForegroundColor Green
        Show-ProgressBar $usedGB $totalGB 40 "    " "Green"
    } catch {}

    # Power Plan
    try {
        $plan = powercfg /getactivescheme 2>&1
        if ($plan -match '\((.+?)\)') {
            $planName = $matches[1]
            $isGaming = $planName -match "Ultimate|High"
            Write-Host "  PWR  " -ForegroundColor Gray -NoNewline
            Write-Host $planName -ForegroundColor $(if($isGaming){"Green"}else{"Yellow"})
        }
    } catch {}

    # OS Version
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem
        $build = [System.Environment]::OSVersion.Version
        Write-Host "  OS   " -ForegroundColor Gray -NoNewline
        Write-Host "$($osInfo.Caption)" -ForegroundColor White -NoNewline
        Write-Host "  ($build)" -ForegroundColor DarkGray
    } catch {}

    Write-Blank

    # Optimization Status
    Get-ActiveStatus
    Write-Host "  OPTIMIZATION STATUS" -ForegroundColor White
    Write-Separator $CH

    Show-StatusDot ($optStatus.HAGS -eq $true) "HAGS (Hardware GPU Scheduling)"
    Show-StatusDot ($optStatus.GameMode -eq $true) "Game Mode"
    Show-StatusDot ($optStatus.GameDVROff -eq $true) "Game DVR Disabled"
    Show-StatusDot ($optStatus.PowerThrottle -eq $true) "Power Throttling Disabled"
    Show-StatusDot ($optStatus.DiagTrack -eq $true) "Telemetry Disabled"
    Show-StatusDot ($optStatus.Widgets -eq $true) "Widgets/Cortana Disabled"
    Show-StatusDot ($optStatus.RawMouse -eq $true) "Raw Mouse Input (no accel)"

    Write-Blank

    $activeCount = @($optStatus.Values | Where-Object { $_ -eq $true }).Count
    $totalCount = $optStatus.Count
    if ($activeCount -eq $totalCount) {
        Write-Host "  [OK] ALL OPTIMIZATIONS ACTIVE ($activeCount/$totalCount)" -ForegroundColor Green
    } else {
        Write-Host "  [!!] $activeCount of $totalCount optimizations active" -ForegroundColor Yellow
    }
    Write-Blank
}

function Show-CategoryMenu {
    param(
        [string]$CategoryName,
        [hashtable[]]$Options
    )

    do {
        Clear-Host
        Show-Header

        Write-Host "  $CategoryName" -ForegroundColor White
        Write-Separator $CH

        $idx = 1
        foreach ($opt in $Options) {
            $labelColor = "White"
            $descColor = "DarkGray"
            if ($opt.ContainsKey("Color")) { $labelColor = $opt.Color }

            Write-Host "  [$idx]  " -ForegroundColor Cyan -NoNewline
            Write-Host $opt.Label -ForegroundColor $labelColor
            if ($opt.ContainsKey("Desc")) {
                Write-Host "       $($opt.Desc)" -ForegroundColor $descColor
            }
            $idx++
        }
        Write-Blank
        Write-Host "  [0]  Back to Main Menu" -ForegroundColor Red
        Write-Blank

        $sel = Read-Host "  Select [0-$($Options.Count)]"

        if ($sel -eq "0") { return }

        $selInt = 0
        if ([int]::TryParse($sel, [ref]$selInt) -and $selInt -ge 1 -and $selInt -le $Options.Count) {
            $chosen = $Options[$selInt - 1]
            if ($chosen.ContainsKey("Script") -and $chosen.Script) {
                Invoke-Script $chosen.Script
            } elseif ($chosen.ContainsKey("Action") -and $chosen.Action) {
                & $chosen.Action
            }
        }
    } while ($true)
}

function Invoke-Script {
    param([string[]]$ScriptNames)
    Clear-Host
    Write-Blank
    Write-Host "  EXECUTING..." -ForegroundColor White
    Write-Separator $CH

    # Prevent modern standby / sleep mid-batch (long NVIDIA/network/SSD scripts)
    try { if ('StayAwake' -as [type]) { [StayAwake]::PreventSleep() } } catch { }

    $failed = @()
    $total = $ScriptNames.Count
    $current = 0

    foreach ($scriptFile in $ScriptNames) {
        $current++
        $scriptPath = Join-Path $scriptDir $scriptFile
        $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($scriptFile)

        Write-Blank
        Write-Host "  [$current/$total] " -ForegroundColor Cyan -NoNewline
        Write-Host $scriptName -ForegroundColor Yellow
        Write-Host "  $SLINE" -ForegroundColor DarkGray

        if (-not (Test-Path -LiteralPath $scriptPath)) {
            Write-Host "  [SKIP] Script not found: $scriptFile" -ForegroundColor Yellow
            $failed += $scriptName
            continue
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            # Dot-source in a nested scope so a terminating error in one script
            # does not tear down the whole launcher session.
            $ErrorActionPreference = 'Stop'
            & $scriptPath
            $ErrorActionPreference = 'Continue'
            $sw.Stop()
            Write-Host ""
            Write-Host "  Completed in $([Math]::Round($sw.Elapsed.TotalSeconds, 1))s" -ForegroundColor DarkGray
        } catch {
            $ErrorActionPreference = 'Continue'
            $sw.Stop()
            Write-Host "  [!] Error: $($_.Exception.Message)" -ForegroundColor Red
            $failed += $scriptName
        }
    }

    # Summary
    Write-Blank
    Write-Host "  EXECUTION SUMMARY" -ForegroundColor White
    Write-Separator $CH

    $succeeded = $total - $failed.Count
    if ($failed.Count -eq 0) {
        Write-Host "  [OK] ALL $total OPERATION(S) COMPLETED" -ForegroundColor Green
    } else {
        Write-Host "  [OK] $succeeded succeeded" -ForegroundColor Green
        Write-Host "  [X]  $($failed.Count) failed:" -ForegroundColor Red
        foreach ($f in $failed) { Write-Host "    - $f" -ForegroundColor Yellow }
    }
    Write-Blank
    Write-Host "  RESTART RECOMMENDED to apply all changes." -ForegroundColor Yellow
    Write-Blank

    Read-Host "  Press Enter to continue"
}

function Invoke-OptimizeAll {
    Clear-Host
    Write-Blank
    Write-Host "  * OPTIMIZE EVERYTHING" -ForegroundColor Yellow
    Write-Separator $CH
    Write-Host "  This runs ALL optimization scripts in the correct order." -ForegroundColor Gray
    Write-Host "  Windows Update compatibility is preserved." -ForegroundColor Green
    Write-Blank

    $confirm = Read-Host "  Type YES to continue"
    if ($confirm -ne "YES") {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        return
    }

    # Optional safety net before touching system settings
    Write-Blank
    $rp = Read-Host "  Create a System Restore point first? (recommended) [Y/n]"
    if ($rp -ne "n" -and $rp -ne "N") {
        Write-Host "  Creating restore point (takes a moment)..." -ForegroundColor Gray
        try {
            Checkpoint-Computer -Description "PC Gaming Optimizer v3.3" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Write-Host "  [OK] Restore point created" -ForegroundColor Green
        } catch {
            # System Restore disabled, or a point was created in the last 24h
            Write-Host "  [--] Could not create restore point: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "       (System Restore may be off, or one was already created today)" -ForegroundColor DarkGray
            $cont = Read-Host "  Continue without a restore point? (y/N)"
            if ($cont -ne "y" -and $cont -ne "Y") { return }
        }
    }

    Invoke-Script @(
        "1_Enable_HAGS.ps1",
        "3_Optimize_NVIDIA.ps1",
        "4_Optimize_Gaming.ps1",
        "5_Kill_Windows_Parasites.ps1",
        "6_Network_Optimization.ps1",
        "10_SSD_Optimization.ps1",
        "11_GPU_MSI_Mode.ps1",
        "12_Timer_Resolution.ps1",
        "15_Input_Latency.ps1",
        "16_Display_Optimizer.ps1",
        "2_Clear_Shader_Cache.ps1"
    )
}

# ---------------------------------------------------------
# ADMIN CHECK
# ---------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Clear-Host
    Write-Blank
    Write-Host "  [!] ADMINISTRATOR REQUIRED" -ForegroundColor Red
    Write-Blank
    Write-Host "  Most optimizations require Administrator privileges." -ForegroundColor Yellow
    Write-Host "  Double-click Run_As_Admin.bat  (recommended)" -ForegroundColor Yellow
    Write-Blank
    $choice = Read-Host "  Continue with limited features? (y/n)"
    if ($choice -ne 'y') {
        try { $Host.UI.RawUI.CursorSize = $script:PrevCursorSize } catch { }
        try { if ('StayAwake' -as [type]) { [StayAwake]::AllowSleep() } } catch { }
        exit 1
    }
}

# ---------------------------------------------------------
# MAIN MENU LOOP
# ---------------------------------------------------------
try {
do {
    Show-Header
    Show-Dashboard

    Write-Host "  MAIN MENU" -ForegroundColor White
    Write-Separator $CH
    Write-Blank

    # One-click
    Write-Host "  [A]  " -ForegroundColor Green -NoNewline
    Write-Host "* OPTIMIZE ALL (recommended)" -ForegroundColor Green
    Write-Host "       Run all scripts in order. Windows Update safe. Sleep blocked." -ForegroundColor DarkGray

    Write-Host "  [G]  " -ForegroundColor Magenta -NoNewline
    Write-Host "> GAME BOOSTER (run before gaming)" -ForegroundColor Magenta
    Write-Host "       RAM purge + DNS flush + holds 0.5ms timer all session" -ForegroundColor DarkGray
    Write-Blank

    # Categories
    Write-Host "  [1]  " -ForegroundColor Cyan -NoNewline
    Write-Host "# GPU & Graphics" -ForegroundColor White
    Write-Host "       HAGS, NVIDIA, GPU MSI Mode" -ForegroundColor DarkGray

    Write-Host "  [2]  " -ForegroundColor Cyan -NoNewline
    Write-Host "# Windows Gaming & Input" -ForegroundColor White
    Write-Host "       Game Mode, Power Plan, Visual Effects, DVR, Mouse/Keyboard" -ForegroundColor DarkGray

    Write-Host "  [3]  " -ForegroundColor Cyan -NoNewline
    Write-Host "# Kill Bloat & Parasites" -ForegroundColor White
    Write-Host "       Telemetry, Copilot, Recall, AI, Cortana, Ads, RAM cleanup" -ForegroundColor DarkGray

    Write-Host "  [4]  " -ForegroundColor Cyan -NoNewline
    Write-Host "# Network" -ForegroundColor White
    Write-Host "       TCP/IP, Nagle, Latency + Encrypted DNS (DoH HTTPS)" -ForegroundColor DarkGray

    Write-Host "  [5]  " -ForegroundColor Cyan -NoNewline
    Write-Host "# Storage & Memory" -ForegroundColor White
    Write-Host "       SSD TRIM, NTFS, Shader Cache, Free RAM" -ForegroundColor DarkGray

    Write-Host "  [6]  " -ForegroundColor Cyan -NoNewline
    Write-Host "# Timer & CPU Scheduling" -ForegroundColor White
    Write-Host "       Timer Resolution, MMCSS, Dynamic Tick" -ForegroundColor DarkGray

    Write-Host "  [7]  " -ForegroundColor Cyan -NoNewline
    Write-Host "# Display & Monitor" -ForegroundColor White
    Write-Host "       Refresh Rate, VRR, G-SYNC, ReBAR detection" -ForegroundColor DarkGray

    Write-Host "  [8]  " -ForegroundColor Cyan -NoNewline
    Write-Host "# Benchmark & System Info" -ForegroundColor White
    Write-Host "       Before/After Snapshot, Metrics Report" -ForegroundColor DarkGray

    Write-Blank

    # Utilities
    Write-Host "  [F]  " -ForegroundColor Yellow -NoNewline
    Write-Host "! Fix Windows Update (repair WU/DISM)" -ForegroundColor Yellow

    Write-Host "  [U]  " -ForegroundColor Red -NoNewline
    Write-Host "< Undo ALL Optimizations" -ForegroundColor Red
    Write-Host "       Restore Windows defaults" -ForegroundColor DarkGray

    Write-Host "  [0]  EXIT" -ForegroundColor Red
    Write-Blank

    $choice = Read-Host "  Select option"

    switch ($choice.ToUpper()) {
        "A" { Invoke-OptimizeAll }

        "G" { Invoke-Script @("14_Game_Booster.ps1") }

        "1" {
            Show-CategoryMenu "GPU & GRAPHICS" @(
                @{ Label = "Enable HAGS"; Desc = "Hardware-Accelerated GPU Scheduling (requires reboot)"; Script = @("1_Enable_HAGS.ps1") }
                @{ Label = "Optimize NVIDIA GPU"; Desc = "PowerMizer max performance, 10GB shader cache, ReBAR check"; Script = @("3_Optimize_NVIDIA.ps1") }
                @{ Label = "Enable GPU MSI Mode"; Desc = "Message Signaled Interrupts for lower latency"; Script = @("11_GPU_MSI_Mode.ps1") }
                @{ Label = "Display & Monitor Check"; Desc = "Refresh rate, VRR, G-SYNC, ReBAR detection + guide"; Script = @("16_Display_Optimizer.ps1") }
                @{ Label = "Clear Shader Caches"; Desc = "NVIDIA, DirectX, Windows caches (fixes stuttering)"; Script = @("2_Clear_Shader_Cache.ps1") }
            )
        }

        "2" {
            Show-CategoryMenu "WINDOWS GAMING & INPUT" @(
                @{ Label = "Full Gaming Optimization"; Desc = "Game Mode, power plan, no-sleep AC, DVR, Focus Assist"; Script = @("4_Optimize_Gaming.ps1") }
                @{ Label = "Input Latency Optimizer"; Desc = "Raw mouse (no accel), kill Sticky Keys popups, keyboard"; Script = @("15_Input_Latency.ps1") }
                @{ Label = "Timer Resolution + MMCSS"; Desc = "Global timer requests, CPU scheduling, frame pacing"; Script = @("12_Timer_Resolution.ps1") }
                @{ Label = "Game Booster (session mode)"; Desc = "RAM purge + DNS flush + holds 0.5ms timer while gaming"; Script = @("14_Game_Booster.ps1") }
            )
        }

        "3" {
            Show-CategoryMenu "KILL BLOAT & PARASITES" @(
                @{ Label = "Kill All Parasites"; Desc = "Telemetry, bloat services, Cortana, ads, tips (WU safe)"; Script = @("5_Kill_Windows_Parasites.ps1") }
                @{ Label = "Free RAM Now"; Desc = "Purge standby list for immediate memory"; Script = @("8_Free_RAM.ps1") }
            )
        }

        "4" {
            Show-CategoryMenu "NETWORK OPTIMIZATION" @(
                @{ Label = "Optimize Network Stack"; Desc = "TCP/IP, DNS cache, Nagle, adapter tuning, QoS"; Script = @("6_Network_Optimization.ps1") }
                @{ Label = "Encrypted DNS (DoH HTTPS)"; Desc = "Quad9 + Mullvad AdBlock over HTTPS tunnel (sibling folder script)"; Action = {
                        $doh = Join-Path (Split-Path $scriptDir -Parent) 'DNS_Set_Encrypted_DoH.ps1'
                        if (-not (Test-Path -LiteralPath $doh)) {
                            $doh = Join-Path $scriptDir '..\DNS_Set_Encrypted_DoH.ps1'
                        }
                        $doh = [System.IO.Path]::GetFullPath($doh)
                        if (Test-Path -LiteralPath $doh) {
                            Clear-Host
                            Write-Host "  Running encrypted DNS apply..." -ForegroundColor Cyan
                            & $doh
                            Read-Host "  Press Enter to continue"
                        } else {
                            Write-Host "  [!!] DNS_Set_Encrypted_DoH.ps1 not found next to this pack." -ForegroundColor Yellow
                            Write-Host "       Expected: $doh" -ForegroundColor DarkGray
                            Read-Host "  Press Enter to continue"
                        }
                    } }
            )
        }

        "5" {
            Show-CategoryMenu "STORAGE & MEMORY" @(
                @{ Label = "SSD / Storage Optimization"; Desc = "TRIM, NTFS tuning, disable power saving"; Script = @("10_SSD_Optimization.ps1") }
                @{ Label = "Clear Shader Caches"; Desc = "Reclaim disk space from GPU cache files"; Script = @("2_Clear_Shader_Cache.ps1") }
                @{ Label = "Free RAM Now"; Desc = "Purge standby list for immediate memory"; Script = @("8_Free_RAM.ps1") }
            )
        }

        "6" {
            Show-CategoryMenu "TIMER & CPU SCHEDULING" @(
                @{ Label = "Timer Resolution + MMCSS"; Desc = "Global timer requests, dynamic tick, CPU scheduling"; Script = @("12_Timer_Resolution.ps1") }
                @{ Label = "Game Booster (session mode)"; Desc = "Holds 0.5ms timer for the whole gaming session"; Script = @("14_Game_Booster.ps1") }
            )
        }

        "7" {
            Invoke-Script @("16_Display_Optimizer.ps1")
        }

        "8" {
            Invoke-Script @("13_Benchmark.ps1")
        }

        "F" {
            Invoke-Script @("7_Fix_Windows_Update.ps1")
        }

        "U" {
            Invoke-Script @("9_Undo_All.ps1")
        }

        "0" {
            Clear-Host
            Write-Blank
            Write-Host "  Thanks for using PC Gaming Optimizer!" -ForegroundColor Cyan
            Write-Host "  Restart your PC to apply all changes." -ForegroundColor Yellow
            Write-Blank
            Write-Host "  +================================================+" -ForegroundColor Cyan
            Write-Host "  |  For best results also:                        |" -ForegroundColor Cyan
            Write-Host "  |  - Update GPU drivers to latest                 |" -ForegroundColor Cyan
            Write-Host "  |  - Use wired Ethernet for gaming                |" -ForegroundColor Cyan
            Write-Host "  |  - Set per-app GPU pref in Settings > Graphics  |" -ForegroundColor Cyan
            Write-Host "  |  - Optional: Encrypted DNS (Network menu)       |" -ForegroundColor Cyan
            Write-Host "  +================================================+" -ForegroundColor Cyan
            Write-Blank
            break
        }
    }
} while ($true)
} finally {
    # Always restore cursor + allow sleep again (no stuck "PC never sleeps" after exit)
    try { $Host.UI.RawUI.CursorSize = $script:PrevCursorSize } catch {
        try { $Host.UI.RawUI.CursorSize = 25 } catch { }
    }
    try { if ('StayAwake' -as [type]) { [StayAwake]::AllowSleep() } } catch { }
}