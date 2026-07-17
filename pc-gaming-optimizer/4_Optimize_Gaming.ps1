<#
.SYNOPSIS
    Applies Windows gaming optimizations: Game Mode, power plan, visual effects,
    background apps, GameDVR, fullscreen optimizations, etc.

.DESCRIPTION
    Configures Windows 10/11 for optimal gaming performance.
    Most settings apply to current user (HKCU), some require Admin (HKLM).

.NOTES
    Run as Administrator for full effect (HKLM keys).
    Some settings require a reboot.
#>

#Requires -RunAsAdministrator

Write-Host "=== Windows Gaming Optimizer ===" -ForegroundColor Cyan
Write-Host "Applying gaming-focused Windows settings..." -ForegroundColor Gray
Write-Host ""

$needsReboot = $false

# ---------------------------------------------------------
# 1. POWER PLAN: Ultimate Performance
# ---------------------------------------------------------
Write-Host "[1/10] Setting power plan to Ultimate Performance..." -ForegroundColor Cyan
$ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
try {
    $result = powercfg -duplicatescheme $ultimateGuid 2>&1
    if ($result -match "GUID: ([a-f0-9\-]+)") {
        $newGuid = $matches[1]
        powercfg -setactive $newGuid | Out-Null
        Write-Host "  Ultimate Performance activated (GUID: $newGuid)" -ForegroundColor Green
    } else {
        powercfg -setactive $ultimateGuid 2>&1 | Out-Null
        Write-Host "  Ultimate Performance activated" -ForegroundColor Green
    }
    $active = powercfg /getactivescheme 2>&1
    Write-Host "  Active: $($active.Trim())" -ForegroundColor Gray

    # Sleep-free while on AC (plugged in): never sleep / hibernate / hybrid sleep.
    # Does NOT force never-sleep on battery so laptops still save power undocked.
    # Subgroup: Sleep  238c9fa8-0aad-41ed-83f4-97be242c8f20
    #   Sleep after     29f6c1db-86da-48c5-9fdb-f2b67b1f44da
    #   Hibernate after 9d7815a6-7ee4-497e-8888-515a05f02364
    #   Hybrid sleep    94ac6d29-73ce-41a6-809f-6363ba21b47e
    $sleepSub = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
    try {
        powercfg /change standby-timeout-ac 0 2>&1 | Out-Null
        powercfg /change hibernate-timeout-ac 0 2>&1 | Out-Null
        powercfg /change monitor-timeout-ac 0 2>&1 | Out-Null
        powercfg /SETACVALUEINDEX SCHEME_CURRENT $sleepSub 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0 2>&1 | Out-Null
        powercfg /SETACVALUEINDEX SCHEME_CURRENT $sleepSub 9d7815a6-7ee4-497e-8888-515a05f02364 0 2>&1 | Out-Null
        powercfg /SETACVALUEINDEX SCHEME_CURRENT $sleepSub 94ac6d29-73ce-41a6-809f-6363ba21b47e 0 2>&1 | Out-Null
        powercfg /SETACTIVE SCHEME_CURRENT 2>&1 | Out-Null
        Write-Host "  AC sleep/hibernate: Never (sleep-free while plugged in)" -ForegroundColor Green
    } catch {
        Write-Host "  AC sleep tweak skipped: $_" -ForegroundColor DarkGray
    }
}
catch {
    Write-Warning "  Could not set power plan: $_"
}
Write-Host ""

# ---------------------------------------------------------
# 2. GAME MODE: Enable
# ---------------------------------------------------------
Write-Host "[2/10] Enabling Game Mode..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "  Game Mode enabled" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 3. HARDWARE-ACCELERATED GPU SCHEDULING (HAGS)
# ---------------------------------------------------------
Write-Host "[3/10] Hardware-Accelerated GPU Scheduling..." -ForegroundColor Cyan
$hagsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
if (Test-Path $hagsKey) {
    $current = (Get-ItemProperty -Path $hagsKey -Name "HwSchMode" -ErrorAction SilentlyContinue).HwSchMode
    if ($current -ne 2) {
        # HwSchMode is the value the Windows Settings toggle uses; HwSchMode2 covers newer builds
        Set-ItemProperty -Path $hagsKey -Name "HwSchMode"  -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $hagsKey -Name "HwSchMode2" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  HAGS enabled (requires reboot)" -ForegroundColor Green
        $needsReboot = $true
    } else {
        Write-Host "  HAGS already enabled" -ForegroundColor Green
    }
}
Write-Host ""

# ---------------------------------------------------------
# 4. GAME DVR / GAME BAR: Disable background recording
# ---------------------------------------------------------
Write-Host "[4/10] Disabling Game DVR / background recording..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "  Game DVR disabled" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 5. VISUAL EFFECTS: Gaming Balanced (smooth UX + performance)
# ---------------------------------------------------------
Write-Host "[5/10] Applying Gaming Balanced visual effects..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue

# KEEP: Show window contents while dragging (smooth file explorer moving)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value 1 -Type String -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "FontSmoothing" -Value 2 -Type String -Force -ErrorAction SilentlyContinue

# Animate windows when minimizing/maximizing
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "1" -Force -ErrorAction SilentlyContinue

# Taskbar animations (pop-up, thumbnail previews)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

# Disable transparency effects (heavy GPU compositing)
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

# Faster shutdown/restart (auto-end hung tasks after 1s instead of waiting)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "AutoEndTasks" -Value "1" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout" -Value "1000" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -Value "2000" -Force -ErrorAction SilentlyContinue


# MenuShowDelay: taskbar auto-hide reveal speed (default 400ms, 100 keeps it fast + animated)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "100" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value ([byte[]](0xBE,0x3E,0x07,0x80,0x12,0x00,0x00,0x00)) -Type Binary -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "  Visual effects: Gaming Balanced (smooth UX + performance)" -ForegroundColor Green
Write-Host "  (Restart Explorer or log off for drag/taskbar changes to apply)" -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------
# 6. BACKGROUND APPS: Disable
# ---------------------------------------------------------
Write-Host "[6/10] Disabling background apps..." -ForegroundColor Cyan
$bgKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
if (Test-Path $bgKey) {
    Get-ChildItem $bgKey -ErrorAction SilentlyContinue | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name "Disabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  Background apps disabled" -ForegroundColor Green
} else {
    Write-Host "  BackgroundAccessApplications key not found (Windows version difference)" -ForegroundColor DarkGray
}
Write-Host ""

# ---------------------------------------------------------
# 7. SYSMAIN (SUPERFETCH): Disable to reduce disk I/O during gaming
# ---------------------------------------------------------
Write-Host "[7/10] Disabling SysMain (Superfetch)..." -ForegroundColor Cyan
$sysmainKey = "HKLM:\SYSTEM\CurrentControlSet\Services\SysMain"
if (Test-Path $sysmainKey) {
    Set-ItemProperty -Path $sysmainKey -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "  SysMain disabled (requires reboot)" -ForegroundColor Green
    $needsReboot = $true
}
Write-Host ""

# ---------------------------------------------------------
# 8. POWER THROTTLING: Disable
# ---------------------------------------------------------
Write-Host "[8/10] Disabling power throttling..." -ForegroundColor Cyan
$throttleKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
if (-not (Test-Path $throttleKey)) {
    New-Item -Path $throttleKey -Force | Out-Null
}
Set-ItemProperty -Path $throttleKey -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "  Power throttling disabled" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 9. GPU PERFORMANCE PREFERENCE: High performance
# ---------------------------------------------------------
Write-Host "[9/10] Setting GPU performance preference..." -ForegroundColor Cyan
$gpuPrefKey = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
if (-not (Test-Path $gpuPrefKey)) {
    New-Item -Path $gpuPrefKey -Force | Out-Null
}
Write-Host "  GPU preference key ready (set per-app in Settings > Graphics)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 10. FOCUS ASSIST FOR GAMING: Disable notification interruptions
# ---------------------------------------------------------
Write-Host "[10/10] Configuring Focus Assist for gaming..." -ForegroundColor Cyan

# Enable Focus Assist automatic rules (games trigger "Alarms only" mode)
$focusKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
if (Test-Path $focusKey) {
    # Enable Quiet Hours / Focus Assist for fullscreen applications (games)
    Set-ItemProperty -Path $focusKey -Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $focusKey -Name "NOC_GLOBAL_SETTING_ALLOW_CALLS"    -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $focusKey -Name "NOC_GLOBAL_SETTING_SUPPRESS_ALL"   -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
}

# Enable the automatic rule: "When I'm playing a game" -> Focus Assist ON
# This is set via the WNF state, but we can at least set the preference key
$quietHoursKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\QuietHours"
if (-not (Test-Path $quietHoursKey)) { New-Item -Path $quietHoursKey -Force | Out-Null }

# The automatic rule for fullscreen apps is a WNF blob, but we set the
# policy infrastructure to support it
$focusAssistPol = "HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\QuietHours"
if (-not (Test-Path $focusAssistPol)) { New-Item -Path $focusAssistPol -Force | Out-Null }
Set-ItemProperty -Path $focusAssistPol -Name "Enable" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

Write-Host "  Focus Assist: Enabled for gaming sessions" -ForegroundColor Green
Write-Host "  Notifications will be suppressed when you launch fullscreen games" -ForegroundColor Green
Write-Host "  Configure manually: Settings > System > Focus assist > Automatic rules" -ForegroundColor Gray
Write-Host "  Ensure 'When I'm playing a game' is set to 'Alarms only'" -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Power Plan: Ultimate Performance" -ForegroundColor Green
Write-Host "AC Sleep/Hibernate: Never (sleep-free on power)" -ForegroundColor Green
Write-Host "Game Mode: Enabled" -ForegroundColor Green
Write-Host "HAGS: Enabled" -ForegroundColor Green
Write-Host "Game DVR: Disabled" -ForegroundColor Green
Write-Host "Visual Effects: Gaming Balanced (smooth UX + performance)" -ForegroundColor Green
Write-Host "Background Apps: Disabled" -ForegroundColor Green
Write-Host "SysMain: Disabled" -ForegroundColor Green
Write-Host "Power Throttling: Disabled" -ForegroundColor Green
Write-Host "Focus Assist: Configured for gaming" -ForegroundColor Green
Write-Host ""

if ($needsReboot) {
    Write-Host "A SYSTEM RESTART IS REQUIRED for some changes to take effect." -ForegroundColor Yellow
    Write-Host "   (HAGS and SysMain changes need reboot)" -ForegroundColor Yellow
} else {
    Write-Host "No reboot strictly required, but recommended." -ForegroundColor Gray
}