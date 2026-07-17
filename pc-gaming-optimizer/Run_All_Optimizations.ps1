<#
.SYNOPSIS
    Master runner for all gaming optimizations.
    Runs scripts in the correct order with proper privilege handling.

.DESCRIPTION
    Executes all optimization scripts in sequence:
    1. Enable HAGS
    2. Optimize NVIDIA GPU
    3. Windows Gaming Settings
    4. Kill Parasites (WU-safe)
    5. Network Optimization
    6. SSD / Storage Optimization
    7. GPU MSI Mode
    8. Timer Resolution + MMCSS
    9. Clear Shader Cache

    Windows Update compatibility is preserved.

.NOTES
    Run as Administrator for full effect.
#>

Write-Host ""
Write-Host "  =================================================" -ForegroundColor Cyan
Write-Host "    ULTIMATE GAMING PC OPTIMIZER  v3.2" -ForegroundColor Yellow
Write-Host "    Windows Update Safe" -ForegroundColor Green
Write-Host "  =================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = $PSScriptRoot
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "  [!] Not running as Administrator." -ForegroundColor Yellow
    Write-Host "  Most optimizations require Admin. Re-run as Admin for full effect." -ForegroundColor Yellow
    Write-Host ""
    $choice = Read-Host "  Continue anyway? (y/n)"
    if ($choice -ne 'y') {
        Write-Host "  Exiting." -ForegroundColor Red
        exit 1
    }
}

$scripts = @(
    @{ Name = "Enable HAGS";                  File = "1_Enable_HAGS.ps1";            RequiresAdmin = $true },
    @{ Name = "Optimize NVIDIA GPU";          File = "3_Optimize_NVIDIA.ps1";        RequiresAdmin = $true },
    @{ Name = "Windows Gaming Settings";      File = "4_Optimize_Gaming.ps1";        RequiresAdmin = $true },
    @{ Name = "Kill Parasites (WU-safe)";     File = "5_Kill_Windows_Parasites.ps1"; RequiresAdmin = $true },
    @{ Name = "Network Optimization";         File = "6_Network_Optimization.ps1";   RequiresAdmin = $true },
    @{ Name = "SSD / Storage Optimization";   File = "10_SSD_Optimization.ps1";      RequiresAdmin = $true },
    @{ Name = "GPU MSI Mode";                 File = "11_GPU_MSI_Mode.ps1";          RequiresAdmin = $true },
    @{ Name = "Timer Resolution + MMCSS";     File = "12_Timer_Resolution.ps1";      RequiresAdmin = $true },
    @{ Name = "Input Latency Optimizer";      File = "15_Input_Latency.ps1";         RequiresAdmin = $true },
    @{ Name = "Display / Monitor Optimizer";  File = "16_Display_Optimizer.ps1";     RequiresAdmin = $false },
    @{ Name = "Clear Shader Cache";           File = "2_Clear_Shader_Cache.ps1";     RequiresAdmin = $false }
)

$failed = @()
$total = $scripts.Count
$current = 0

foreach ($script in $scripts) {
    $current++
    $scriptPath = Join-Path $scriptDir $script.File

    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [$current/$total] $($script.Name)" -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray

    if (-not (Test-Path $scriptPath)) {
        Write-Host "  [SKIP] Script not found: $($script.File)" -ForegroundColor Yellow
        $failed += "$($script.Name) - not found"
        continue
    }

    if ($script.RequiresAdmin -and -not $isAdmin) {
        Write-Host "  [SKIP] Requires Admin: $($script.Name)" -ForegroundColor Yellow
        $failed += "$($script.Name) - needs Admin"
        continue
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & "$scriptPath"
        $sw.Stop()
        Write-Host "  Completed in $([Math]::Round($sw.Elapsed.TotalSeconds, 1))s" -ForegroundColor DarkGray
    }
    catch {
        $sw.Stop()
        Write-Host "  [!] Error: $_" -ForegroundColor Red
        $failed += "$($script.Name) - exception"
    }
    Write-Host ""
}

# Summary
Write-Host ""
Write-Host "  =================================================" -ForegroundColor Cyan
Write-Host "    SUMMARY" -ForegroundColor Yellow
Write-Host "  =================================================" -ForegroundColor Cyan
Write-Host ""

$succeeded = $total - $failed.Count
if ($failed.Count -eq 0) {
    Write-Host "  All $total optimizations completed successfully!" -ForegroundColor Green
} else {
    Write-Host "  $succeeded of $total completed successfully." -ForegroundColor Green
    Write-Host "  $($failed.Count) had issues:" -ForegroundColor Yellow
    foreach ($f in $failed) {
        Write-Host "    - $f" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "  RECOMMENDATION: Restart your PC to apply all changes." -ForegroundColor Yellow
Write-Host ""
Write-Host "  For best results also:" -ForegroundColor Gray
Write-Host "    - Update GPU drivers to latest" -ForegroundColor Gray
Write-Host "    - Set per-app GPU preference to 'High Performance' in Settings > Graphics" -ForegroundColor Gray
Write-Host "    - In NVIDIA Control Panel: Power Management = Prefer Maximum Performance" -ForegroundColor Gray
Write-Host "    - Use wired Ethernet for lowest latency" -ForegroundColor Gray
Write-Host ""