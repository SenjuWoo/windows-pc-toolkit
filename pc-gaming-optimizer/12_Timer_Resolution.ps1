<#
.SYNOPSIS
    Optimizes Windows system timer resolution for better frame pacing.

.DESCRIPTION
    Sets the Windows multimedia timer to 0.5ms (5000 100-ns ticks) for
    smoother frame delivery and reduced input latency. Also disables
    dynamic tick for consistent timing.

    Many games benefit from consistent timer resolution because Windows
    defaults to 15.625ms (64 Hz) which can cause micro-stuttering.

.NOTES
    Requires Administrator privileges. Takes effect immediately.
    Reverts to default on reboot unless configured otherwise.
#>

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "  >> TIMER RESOLUTION OPTIMIZER" -ForegroundColor Cyan
Write-Host "  Setting system timer to 0.5ms for smooth frame pacing..." -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------
# 1. CHECK CURRENT TIMER RESOLUTION
# ---------------------------------------------------------
Write-Host "  [1/4] Checking current timer resolution..." -ForegroundColor Cyan

try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TimerHelper {
    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern uint NtQueryTimerResolution(out uint MinimumResolution, out uint MaximumResolution, out uint CurrentResolution);

    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern uint NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution);
}
"@

    $minRes = 0; $maxRes = 0; $curRes = 0
    [TimerHelper]::NtQueryTimerResolution([ref]$minRes, [ref]$maxRes, [ref]$curRes) | Out-Null

    # Values are in 100-nanosecond ticks
    $curMs = [math]::Round($curRes / 10000, 2)
    $minMs = [math]::Round($minRes / 10000, 2)
    $maxMs = [math]::Round($maxRes / 10000, 2)
    Write-Host "    Current: ${curMs}ms | Min: ${maxMs}ms | Max: ${minMs}ms" -ForegroundColor Gray
}
catch {
    Write-Host "    Could not query timer resolution" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# 2. SET TIMER RESOLUTION TO 0.5ms
# ---------------------------------------------------------
Write-Host "  [2/4] Setting timer resolution to 0.5ms..." -ForegroundColor Cyan

try {
    $newRes = 5000  # 0.5ms in 100-nanosecond units
    $actualRes = 0
    $result = [TimerHelper]::NtSetTimerResolution($newRes, $true, [ref]$actualRes)
    if ($result -eq 0) {
        $actualMs = [math]::Round($actualRes / 10000, 2)
        Write-Host "    Timer resolution set to ${actualMs}ms" -ForegroundColor Green
        Write-Host "    NOTE: this request only lasts while a process holds it." -ForegroundColor Yellow
        Write-Host "    Use 14_Game_Booster.ps1 to HOLD 0.5ms during a gaming session." -ForegroundColor Yellow
    }
    else {
        Write-Host "    NtSetTimerResolution returned NTSTATUS: $result" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "    Could not set timer resolution: $_" -ForegroundColor Yellow
}

# Windows 11 (and Win10 2004+) ignores minimized/background apps' timer requests
# unless this kernel flag is set - critical for borderless-windowed gaming
$kernelKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
if (Test-Path $kernelKey) {
    Set-ItemProperty -Path $kernelKey -Name "GlobalTimerResolutionRequests" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "    Global timer resolution requests: ENABLED (honors game timer requests system-wide)" -ForegroundColor Green
}
Write-Host ""

# ---------------------------------------------------------
# 3. DISABLE DYNAMIC TICK (consistent timing for gaming)
# ---------------------------------------------------------
Write-Host "  [3/4] Configuring dynamic tick..." -ForegroundColor Cyan

try {
    $bcdResult = bcdedit /set disabledynamictick yes 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    Dynamic tick disabled (consistent timer behavior)" -ForegroundColor Green
    }
    else {
        Write-Host "    Could not set dynamic tick (may already be set)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "    Could not configure dynamic tick: $_" -ForegroundColor Yellow
}

# Make sure HPET is NOT forced as the clock source. Forcing useplatformclock
# adds clock-read overhead and hurts frame times on modern CPUs - the default
# TSC (invariant timestamp counter) is faster and what Windows expects.
try {
    bcdedit /deletevalue useplatformclock 2>&1 | Out-Null
    Write-Host "    Clock source: default TSC (HPET forcing removed - better frame times)" -ForegroundColor Green
}
catch {
    Write-Host "    Clock source: already default" -ForegroundColor Green
}
Write-Host ""

# ---------------------------------------------------------
# 4. MMCSS (Multimedia Class Scheduler) TUNING
# ---------------------------------------------------------
Write-Host "  [4/4] Tuning MMCSS for gaming..." -ForegroundColor Cyan

$mmcssKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
if (Test-Path $mmcssKey) {
    # SystemResponsiveness = 0 (dedicate more CPU to multimedia/gaming)
    Set-ItemProperty -Path $mmcssKey -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "    System responsiveness: 0 (max CPU for gaming)" -ForegroundColor Green
}

$mmcssGamesKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
if (Test-Path $mmcssGamesKey) {
    Set-ItemProperty -Path $mmcssGamesKey -Name "GPU Priority"        -Value 8        -Type DWord  -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssGamesKey -Name "Priority"            -Value 6        -Type DWord  -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssGamesKey -Name "Scheduling Category" -Value "High"   -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssGamesKey -Name "SFIO Priority"       -Value "High"   -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssGamesKey -Name "Background Only"     -Value "False"  -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssGamesKey -Name "Clock Rate"          -Value 10000    -Type DWord  -Force -ErrorAction SilentlyContinue
    Write-Host "    MMCSS Games profile: GPU priority=8, Scheduling=High" -ForegroundColor Green
}

# Also optimize CPU scheduling priority separation
# 38 decimal = 0x26 = short quanta, variable, 3:1 foreground boost (gaming standard)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    CPU priority separation: Gaming optimized (foreground boost)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
Write-Host "  === TIMER RESOLUTION OPTIMIZATION COMPLETE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Applied:" -ForegroundColor White
Write-Host "    - Global timer resolution requests: Enabled (persistent)" -ForegroundColor Green
Write-Host "    - Dynamic tick: Disabled (consistent timing)" -ForegroundColor Green
Write-Host "    - Clock source: Default TSC (HPET not forced)" -ForegroundColor Green
Write-Host "    - MMCSS Games: High GPU/CPU priority" -ForegroundColor Green
Write-Host "    - CPU scheduling: Foreground boost for gaming" -ForegroundColor Green
Write-Host ""
Write-Host "  NOTE: The 0.5ms timer only holds while a process requests it." -ForegroundColor Yellow
Write-Host "  Use 14_Game_Booster.ps1 before gaming - it holds 0.5ms for the whole session." -ForegroundColor Yellow
Write-Host ""