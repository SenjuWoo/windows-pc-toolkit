<#
.SYNOPSIS
    Enables Hardware-Accelerated GPU Scheduling (HAGS) on Windows 10/11.
    Requires Administrator privileges.

.DESCRIPTION
    Sets HwSchMode (the documented HAGS toggle) to 2 (enabled) under
    HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers. HwSchMode2 is
    also written for newer builds that read it.
    A restart is required for changes to take effect.

.NOTES
    Run as Administrator.
#>

#Requires -RunAsAdministrator

Write-Host "=== Enabling Hardware-Accelerated GPU Scheduling (HAGS) ===" -ForegroundColor Cyan

$keyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
$desiredValue = 2  # 1 = Off, 2 = On

if (-not (Test-Path $keyPath)) {
    Write-Error "GraphicsDrivers registry key not found. Are you on Windows 10/11?"
    exit 1
}

try {
    # HwSchMode is the value the Windows Settings toggle uses; HwSchMode2 covers newer builds
    Set-ItemProperty -Path $keyPath -Name "HwSchMode"  -Value $desiredValue -Type DWord -Force -ErrorAction Stop
    Set-ItemProperty -Path $keyPath -Name "HwSchMode2" -Value $desiredValue -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "HAGS enabled successfully (HwSchMode = $desiredValue)" -ForegroundColor Green

    # Verify
    $actual = (Get-ItemProperty -Path $keyPath -Name "HwSchMode" -ErrorAction Stop).HwSchMode
    if ($actual -eq $desiredValue) {
        Write-Host "Verified: HAGS is now ON" -ForegroundColor Green
    } else {
        Write-Warning "Value set but verification shows: $actual"
    }
}
catch {
    Write-Error "Failed to set HAGS: $_"
    exit 1
}

Write-Host ""
Write-Host "NOTE: A system restart is required for HAGS to take effect." -ForegroundColor Yellow