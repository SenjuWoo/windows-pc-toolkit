<#
.SYNOPSIS
    Optimizes mouse and keyboard input for gaming - raw 1:1 aim and no
    surprise accessibility popups mid-match.

.DESCRIPTION
    1. Disables Enhanced Pointer Precision (mouse acceleration) so mouse
       movement maps 1:1 to cursor/aim movement - essential for consistent
       muscle memory in shooters. Applied immediately via SystemParametersInfo.
    2. Disables the Sticky Keys / Filter Keys / Toggle Keys HOTKEYS
       (pressing Shift 5x or holding Shift 8s mid-game pops a focus-stealing
       dialog - the classic ranked-match killer).
    3. Sets keyboard repeat delay to shortest.

    Your in-game sensitivity is NOT touched.

.NOTES
    Requires Administrator privileges (kept consistent with the other scripts;
    values themselves are per-user). Applied instantly - no reboot needed.
    9_Undo_All.ps1 restores Windows defaults.
#>

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "  >> INPUT LATENCY OPTIMIZER" -ForegroundColor Cyan
Write-Host "  Raw mouse input + no accessibility popups mid-game..." -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------
# 1. MOUSE ACCELERATION OFF (Enhanced Pointer Precision)
# ---------------------------------------------------------
Write-Host "  [1/3] Disabling mouse acceleration (Enhanced Pointer Precision)..." -ForegroundColor Cyan

Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed"      -Value "0" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Force -ErrorAction SilentlyContinue

# Apply immediately (registry alone needs a logoff) - SPI_SETMOUSE = 0x0004
try {
    $spiSource = @'
using System;
using System.Runtime.InteropServices;
public static class MouseParams
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);

    // SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 0x01 | 0x02
    public static bool SetAcceleration(int on)
    {
        int[] mouseParams = new int[] { 0, 0, on };
        return SystemParametersInfo(0x0004, 0, mouseParams, 0x03);
    }
}
'@
    if (-not ("MouseParams" -as [type])) {
        Add-Type -TypeDefinition $spiSource -ErrorAction Stop
    }
    if ([MouseParams]::SetAcceleration(0)) {
        Write-Host "    Mouse acceleration: OFF (applied instantly, 1:1 raw movement)" -ForegroundColor Green
    } else {
        Write-Host "    Registry set - takes effect at next sign-in" -ForegroundColor Yellow
    }
} catch {
    Write-Host "    Registry set - takes effect at next sign-in" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# 2. ACCESSIBILITY HOTKEYS OFF (focus-stealing popups)
# ---------------------------------------------------------
Write-Host "  [2/3] Disabling Sticky/Filter/Toggle Keys hotkeys..." -ForegroundColor Cyan

# Flags with the "hotkey active" and "confirmation" bits cleared
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\StickyKeys"        -Name "Flags" -Value "506" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\ToggleKeys"        -Name "Flags" -Value "58"  -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "Flags" -Value "122" -Force -ErrorAction SilentlyContinue

Write-Host "    Shift x5 / Shift-hold popups: DISABLED (no more mid-match interruptions)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 3. KEYBOARD REPEAT DELAY: SHORTEST
# ---------------------------------------------------------
Write-Host "  [3/3] Setting keyboard repeat delay to shortest..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "0" -Force -ErrorAction SilentlyContinue
Write-Host "    Keyboard repeat delay: 0 (shortest)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
Write-Host "  === INPUT OPTIMIZATION COMPLETE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Applied:" -ForegroundColor White
Write-Host "    - Mouse acceleration OFF (1:1 raw input for consistent aim)" -ForegroundColor Green
Write-Host "    - Sticky/Filter/Toggle Keys popups OFF" -ForegroundColor Green
Write-Host "    - Keyboard repeat delay: shortest" -ForegroundColor Green
Write-Host ""
Write-Host "  Tips for even lower input lag:" -ForegroundColor Gray
Write-Host "    - Set your mouse to 1000Hz+ polling in its software" -ForegroundColor Gray
Write-Host "    - Use exclusive fullscreen (or Win11 optimized borderless)" -ForegroundColor Gray
Write-Host "    - Cap FPS slightly below refresh rate with VRR/G-Sync" -ForegroundColor Gray
