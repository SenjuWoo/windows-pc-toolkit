<#
.SYNOPSIS
    Optimizes NVIDIA driver settings for maximum performance gaming.
    Sets PowerMizer to "Prefer Maximum Performance" and increases shader cache size.

.DESCRIPTION
    Modifies NVIDIA driver registry keys to prefer maximum performance
    and sets a generous shader cache limit. Works on any PC with NVIDIA GPU.

.NOTES
    Requires Administrator privileges.
    Some settings require a reboot to take full effect.
#>

#Requires -RunAsAdministrator

Write-Host "=== NVIDIA Performance Optimizer ===" -ForegroundColor Cyan
Write-Host "Configuring driver for maximum performance..." -ForegroundColor Gray
Write-Host ""

$classGuid = "{4d36e968-e325-11ce-bfc1-08002be10318}"
$basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$classGuid"

if (-not (Test-Path $basePath)) {
    Write-Error "Display adapter class key not found."
    exit 1
}

$nvidiaAdapters = Get-ChildItem $basePath -ErrorAction SilentlyContinue | Where-Object {
    ($_.GetValue("DriverDesc") -like "*NVIDIA*")
}

if ($nvidiaAdapters.Count -eq 0) {
    Write-Warning "No NVIDIA GPU found in registry. Skipping NVIDIA optimizations."
    return
}

foreach ($adapter in $nvidiaAdapters) {
    $desc = $adapter.GetValue("DriverDesc")
    Write-Host "Found NVIDIA adapter: $desc" -ForegroundColor Green
    Write-Host "  Registry path: $($adapter.PSPath)" -ForegroundColor Gray
    
    # --- Driver version ---
    $driverVer = $adapter.GetValue("DriverVersion")
    if ($driverVer) { Write-Host "  Driver version: $driverVer" -ForegroundColor Cyan }
    
    # --- ReBAR detection ---
    $rebarDetected = $false
    $featureControl = $adapter.GetValue("FeatureControl")
    $rmGpuId = $adapter.GetValue("RMGpuId")
    # RTX 30-series+ (GPU ID > 0x2000 in NVIDIA encoding) support ReBAR
    if ($rmGpuId) {
        $gpuIdHex = if ($rmGpuId -is [int]) { "0x{0:X}" -f $rmGpuId } else { "$rmGpuId" }
        Write-Host "  GPU ID: $gpuIdHex" -ForegroundColor DarkGray
        # RTX 30-series = 0x2200+, RTX 40-series = 0x2600+
        if ($rmGpuId -is [int] -and $rmGpuId -ge 0x2000) {
            $rebarDetected = $true
            Write-Host "  Resizable BAR: GPU supports it (RTX 30-series+)" -ForegroundColor Green
            Write-Host "    Verify in: NVIDIA Control Panel > System Info > 'Resizable BAR'" -ForegroundColor Gray
            Write-Host "    If 'No': enable Above 4G Decoding + Re-Size BAR in BIOS" -ForegroundColor Yellow
        }
    }
    if (-not $rebarDetected) {
        Write-Host "  Resizable BAR: Check in NVIDIA Control Panel > System Info" -ForegroundColor Gray
    }
    
    # --- Apply optimizations ---
    try {
        Set-ItemProperty -Path $adapter.PSPath -Name "PowerMizerEnable"       -Value 1     -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $adapter.PSPath -Name "PowerMizerLevel"        -Value 1     -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $adapter.PSPath -Name "PowerMizerLevelAC"      -Value 1     -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $adapter.PSPath -Name "PerLevelGPUCacheSize"   -Value 1     -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $adapter.PSPath -Name "ShaderCacheSize"        -Value 10240 -Type DWord -Force -ErrorAction Stop
        Write-Host "  PowerMizer: Prefer Maximum Performance" -ForegroundColor Green
        Write-Host "  Shader cache size: 10 GB (10240 MB)" -ForegroundColor Green
    }
    catch {
        Write-Warning "  Some settings could not be applied: $_"
    }
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "Note: A system restart is recommended for all changes to take effect." -ForegroundColor Yellow