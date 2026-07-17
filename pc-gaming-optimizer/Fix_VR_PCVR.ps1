<#
.SYNOPSIS
    VR / PCVR REPAIR - reverts ONLY the optimizer settings that degrade
    SteamVR and overlay apps (OVR Toolkit), while keeping the good gaming
    tweaks (Ultimate Performance power plan, GPU MSI mode, SSD, input).

.DESCRIPTION
    Targeted counterpart to 9_Undo_All.ps1. Reverts, for a WIRELESS PCVR
    setup (Virtual Desktop / Air Link / ALVR):
      1. HAGS (Hardware-Accelerated GPU Scheduling) -> OFF   [needs reboot]
      2. MMCSS SystemResponsiveness  0 -> 20 (Windows default)
      3. CPU Win32PrioritySeparation 38 -> 2 (Windows default)
      4. MMCSS "Games" profile        -> Windows defaults (drops forced 0.1ms)
      5. NetworkThrottlingIndex 0xFFFFFFFF -> 10 (Windows default)
      6. Nagle's algorithm (TcpAckFrequency / TCPNoDelay) removed from all NICs

    KEPT ON PURPOSE (good for VR): GPU MSI mode, Ultimate Performance power
    plan, power throttling off, SSD tuning, mouse/keyboard input tweaks.

.NOTES
    Run as Administrator. REBOOT afterwards for the HAGS change to take effect.
#>

# --- self-elevate (path has spaces, so quote it) ---
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  Elevating to Administrator..." -ForegroundColor Yellow
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") `
        -Verb RunAs
    exit
}

Write-Host ""
Write-Host "  >> VR / PCVR REPAIR (targeted, wireless)" -ForegroundColor Cyan
Write-Host "  Reverting only the settings that hurt SteamVR / OVR Toolkit..." -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------
# 1. HAGS OFF  (prime suspect for overlay problems)
# ---------------------------------------------------------
Write-Host "  [1/6] Disabling Hardware-Accelerated GPU Scheduling (HAGS)..." -ForegroundColor Cyan
$gfx = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
# 1 = Off, 2 = On (this is exactly what the Windows Settings toggle writes)
Set-ItemProperty -Path $gfx -Name "HwSchMode"  -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $gfx -Name "HwSchMode2" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    HAGS set to OFF (takes effect after reboot)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 2. MMCSS SystemResponsiveness -> 20 (Windows default)
# ---------------------------------------------------------
Write-Host "  [2/6] Restoring MMCSS SystemResponsiveness..." -ForegroundColor Cyan
$sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 20 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    SystemResponsiveness: 0 -> 20 (restores CPU reserve for overlay + audio)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 3. CPU Win32PrioritySeparation -> 2 (Windows default)
# ---------------------------------------------------------
Write-Host "  [3/6] Restoring CPU priority separation..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Win32PrioritySeparation: 38 -> 2 (stops starving the background overlay)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 4. MMCSS "Games" profile -> Windows defaults
# ---------------------------------------------------------
Write-Host "  [4/6] Restoring MMCSS Games profile defaults..." -ForegroundColor Cyan
$mmcssGames = "$sysProfile\Tasks\Games"
if (Test-Path $mmcssGames) {
    Set-ItemProperty -Path $mmcssGames -Name "GPU Priority"        -Value 8        -Type DWord  -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssGames -Name "Priority"            -Value 2        -Type DWord  -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssGames -Name "Scheduling Category" -Value "Medium" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssGames -Name "SFIO Priority"       -Value "Normal" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssGames -Name "Background Only"     -Value "True"   -Type String -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $mmcssGames -Name "Clock Rate" -Force -ErrorAction SilentlyContinue
    Write-Host "    Games profile restored (dropped forced 0.1ms / high priority)" -ForegroundColor Green
} else {
    Write-Host "    Games profile key not present (nothing to do)" -ForegroundColor DarkGray
}
Write-Host ""

# ---------------------------------------------------------
# 5. NetworkThrottlingIndex -> 10 (Windows default)  [wireless VR]
# ---------------------------------------------------------
Write-Host "  [5/6] Restoring network throttling (wireless VR streaming)..." -ForegroundColor Cyan
Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    NetworkThrottlingIndex: disabled -> 10 (default; helps streamed audio/video pacing)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 6. Remove Nagle overrides from all interfaces  [wireless VR]
# ---------------------------------------------------------
Write-Host "  [6/6] Removing Nagle/ACK overrides from network adapters..." -ForegroundColor Cyan
$ifc = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
$cleared = 0
Get-ChildItem $ifc -ErrorAction SilentlyContinue | ForEach-Object {
    $had = $false
    foreach ($v in @("TcpAckFrequency","TCPNoDelay","TcpDelAckTicks")) {
        if ($null -ne (Get-ItemProperty -Path $_.PSPath -Name $v -ErrorAction SilentlyContinue).$v) { $had = $true }
        Remove-ItemProperty -Path $_.PSPath -Name $v -Force -ErrorAction SilentlyContinue
    }
    if ($had) { $cleared++ }
}
Write-Host "    Cleared Nagle overrides on $cleared adapter interface(s)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# VERIFY
# ---------------------------------------------------------
Write-Host "  === VERIFY (post-change) ===" -ForegroundColor Cyan
$gv  = Get-ItemProperty $gfx -Name HwSchMode -EA SilentlyContinue
$srv = (Get-ItemProperty $sysProfile -Name SystemResponsiveness -EA SilentlyContinue).SystemResponsiveness
$psv = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name Win32PrioritySeparation -EA SilentlyContinue).Win32PrioritySeparation
$nti = (Get-ItemProperty $sysProfile -Name NetworkThrottlingIndex -EA SilentlyContinue).NetworkThrottlingIndex
Write-Host ("    HAGS HwSchMode         = {0}  (want 1 = OFF)" -f $gv.HwSchMode) -ForegroundColor Gray
Write-Host ("    SystemResponsiveness   = {0}  (want 20)" -f $srv) -ForegroundColor Gray
Write-Host ("    Win32PrioritySeparation= {0}  (want 2)" -f $psv) -ForegroundColor Gray
Write-Host ("    NetworkThrottlingIndex = {0}  (want 10)" -f $nti) -ForegroundColor Gray
Write-Host ""

Write-Host "  ================================================" -ForegroundColor Green
Write-Host "   VR REPAIR COMPLETE" -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  KEPT (good for VR): GPU MSI mode, Ultimate Performance power" -ForegroundColor DarkGray
Write-Host "  plan, power throttling off, SSD tuning, input tweaks." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  >> REBOOT NOW - the HAGS change only applies after a restart." -ForegroundColor Yellow
Write-Host ""
Read-Host "  Press Enter to close"
