<#
.SYNOPSIS
    Optimizes SSD performance for gaming - TRIM, I/O scheduling, NTFS tweaks.

.DESCRIPTION
    Enables TRIM on all SSDs, disables last-access timestamps, optimizes
    NTFS memory behavior, disables 8.3 short name generation, and tunes
    the storage stack for minimum latency.

.NOTES
    Requires Administrator privileges. Changes take effect immediately.
#>

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "  >> SSD OPTIMIZATION" -ForegroundColor Cyan
Write-Host "  Tuning storage stack for minimum latency..." -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------
# 1. ENABLE TRIM ON ALL SSDs
# ---------------------------------------------------------
Write-Host "  [1/5] Enabling TRIM on all SSDs..." -ForegroundColor Cyan
try {
    $result = fsutil behavior query DisableDeleteNotify 2>&1
    # DisableDeleteNotify = 0 means TRIM is enabled
    $ssdTrim = fsutil behavior set DisableDeleteNotify 0 2>&1
    Write-Host "    TRIM enabled (DisableDeleteNotify = 0)" -ForegroundColor Green
}
catch {
    Write-Host "    Could not configure TRIM: $_" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# 2. DISABLE LAST ACCESS TIMESTAMP (reduces write I/O)
# ---------------------------------------------------------
Write-Host "  [2/5] Disabling NTFS last-access timestamps..." -ForegroundColor Cyan
try {
    $result = fsutil behavior set DisableLastAccess 1 2>&1
    Write-Host "    Last-access timestamps disabled (reduces unnecessary writes)" -ForegroundColor Green
}
catch {
    Write-Host "    Could not set DisableLastAccess: $_" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# 3. DISABLE 8.3 SHORT FILE NAMES (faster directory lookups)
# ---------------------------------------------------------
Write-Host "  [3/5] Disabling 8.3 short file name generation..." -ForegroundColor Cyan
try {
    $result = fsutil behavior set disable8dot3 1 2>&1
    Write-Host "    8.3 name generation disabled (faster NTFS lookups)" -ForegroundColor Green
}
catch {
    Write-Host "    Could not set 8dot3: $_" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# 4. NTFS MEMORY & I/O TUNING
# ---------------------------------------------------------
Write-Host "  [4/5] Tuning NTFS memory and I/O settings..." -ForegroundColor Cyan

# Increase NTFS paged/non-paged pool memory for faster file operations
$ntfsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
if (Test-Path $ntfsKey) {
    # NtfsDisable8dot3NameCreation = 1 (already set via fsutil above, belt-and-suspenders)
    Set-ItemProperty -Path $ntfsKey -Name "NtfsDisable8dot3NameCreation" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    # NtfsDisableLastAccessUpdate = 80000003 (system-managed + user-disabled)
    Set-ItemProperty -Path $ntfsKey -Name "NtfsDisableLastAccessUpdate" -Value 2147483651 -Type DWord -Force -ErrorAction SilentlyContinue

    # NtfsMemoryUsage = 2 (increase paged pool for large file operations)
    Set-ItemProperty -Path $ntfsKey -Name "NtfsMemoryUsage" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

    # PathCache (increase directory path cache size)
    Set-ItemProperty -Path $ntfsKey -Name "PathCache" -Value 128 -Type DWord -Force -ErrorAction SilentlyContinue

    # NameCache (increase file name cache size)
    Set-ItemProperty -Path $ntfsKey -Name "NameCache" -Value 16384 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Host "    NTFS memory pools: Increased for large file operations" -ForegroundColor Green
    Write-Host "    Path/Name cache: Expanded for faster lookups" -ForegroundColor Green
}
Write-Host ""

# ---------------------------------------------------------
# 5. DISABLE STORAGE DEVICE POWERSAVING (prevents spin-down latency)
# ---------------------------------------------------------
Write-Host "  [5/5] Disabling storage device power saving..." -ForegroundColor Cyan

# Disable disk idle timeout (prevents spin-down during gaming)
$diskKey = "HKLM:\SYSTEM\CurrentControlSet\Services\disk"
if (Test-Path $diskKey) {
    # TimeOutValue = 0 means no timeout for disk standby
    Set-ItemProperty -Path $diskKey -Name "TimeOutValue" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "    Disk idle timeout disabled (no spin-down during gaming)" -ForegroundColor Green
}

# Disable AHCI link power management (prevents NVMe/SATA sleep)
$ahciKey = "HKLM:\SYSTEM\CurrentControlSet\Services\storahci\Parameters\Device"
if (-not (Test-Path $ahciKey)) {
    New-Item -Path $ahciKey -Force | Out-Null
}
# Disable LPM (Link Power Management) for all ports
$noLpm = @()
for ($i = 0; $i -lt 16; $i++) { $noLpm += "0" }
Set-ItemProperty -Path $ahciKey -Name "NoLPM" -Value ([byte[]]($noLpm | ForEach-Object { [byte]$_ })) -Type Binary -Force -ErrorAction SilentlyContinue
Write-Host "    AHCI Link Power Management disabled" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
Write-Host "  === SSD OPTIMIZATION COMPLETE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Applied:" -ForegroundColor White
Write-Host "    - TRIM enabled on all SSDs" -ForegroundColor Green
Write-Host "    - NTFS last-access timestamps disabled" -ForegroundColor Green
Write-Host "    - 8.3 short name generation disabled" -ForegroundColor Green
Write-Host "    - NTFS memory pools increased" -ForegroundColor Green
Write-Host "    - Storage power saving disabled" -ForegroundColor Green
Write-Host ""
Write-Host "  These reduce write amplification and storage latency during gaming." -ForegroundColor Gray