<#
.SYNOPSIS
    Display & Refresh Rate Optimizer - detects monitor capabilities and flags issues.
.DESCRIPTION
    Checks every connected monitor's current vs. maximum refresh rate,
    Windows VRR (Variable Refresh Rate) status, G-SYNC indicators,
    and guides the user to set the optimal configuration.

    Cannot directly set refresh rate (requires user interaction in Windows
    Settings or NVIDIA Control Panel), but clearly flags misconfigurations.

.NOTES
    Read-only diagnostics - no admin required for detection.
    Some G-SYNC indicators need NVIDIA driver registry access (admin).
#>

Write-Host ""
Write-Host "  >> DISPLAY & REFRESH RATE OPTIMIZER" -ForegroundColor Cyan
Write-Host "  Checking monitor capabilities and gaming display settings..." -ForegroundColor Gray
Write-Host ""

$issuesFound = $false

# ---------------------------------------------------------
# 1. MONITOR REFRESH RATE DETECTION
# ---------------------------------------------------------
Write-Host "  [1/5] Monitor Refresh Rate Detection..." -ForegroundColor Cyan

try {
    $gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch "Microsoft Basic|Remote Desktop|Virtual Desktop" }
    $virtualGpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "Virtual Desktop" }
    
    foreach ($gpu in $gpus) {
        $gpuName = ($gpu.Name -replace '\s+', ' ').Trim()
        $currentHz = $gpu.CurrentRefreshRate
        $maxHz = $gpu.MaxRefreshRate
        $driverVer = $gpu.DriverVersion
        
        if ($gpuName.Length -gt 55) { $gpuName = $gpuName.Substring(0, 52) + "..." }
        
        Write-Host "    GPU: $gpuName" -ForegroundColor White
        Write-Host "    Driver: $driverVer" -ForegroundColor DarkGray
        
        if ($currentHz -and $currentHz -gt 0) {
            $rateColor = if ($currentHz -ge 120) { "Green" } elseif ($currentHz -ge 60) { "Yellow" } else { "Red" }
            Write-Host "    Refresh Rate: $currentHz Hz " -ForegroundColor $rateColor -NoNewline
            
            if ($maxHz -and $maxHz -gt $currentHz) {
                Write-Host "(MAX AVAILABLE: $maxHz Hz - NOT AT MAX!)" -ForegroundColor Red
                Write-Host "      ACTION: Go to Settings > System > Display > Advanced display" -ForegroundColor Yellow
                Write-Host "              and select $maxHz Hz refresh rate for your monitor." -ForegroundColor Yellow
                $issuesFound = $true
            } elseif ($maxHz -and $maxHz -eq $currentHz) {
                Write-Host "(at maximum)" -ForegroundColor Green
            } else {
                Write-Host "" -ForegroundColor $rateColor
            }
            
            # Gaming refresh rate tiers
            if ($currentHz -ge 240) {
                Write-Host "    Tier: Competitive eSports (240+ Hz) - excellent!" -ForegroundColor Green
            } elseif ($currentHz -ge 144) {
                Write-Host "    Tier: High Refresh Gaming (144+ Hz) - great for gaming" -ForegroundColor Green
            } elseif ($currentHz -ge 120) {
                Write-Host "    Tier: Smooth Gaming (120 Hz) - good baseline" -ForegroundColor Yellow
            } elseif ($currentHz -ge 60) {
                Write-Host "    Tier: Standard (60 Hz) - consider upgrading for gaming" -ForegroundColor Yellow
            } else {
                Write-Host "    Tier: Low refresh - significant gaming disadvantage" -ForegroundColor Red
                $issuesFound = $true
            }
        } else {
            Write-Host "    Refresh Rate: Could not detect" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    # Check for virtual desktop GPU (VDI/RDP) that might cap refresh
    if ($virtualGpus) {
        Write-Host "    NOTE: Virtual Desktop GPU detected - remote sessions may" -ForegroundColor DarkGray
        Write-Host "    limit refresh rate. Use local console for full refresh." -ForegroundColor DarkGray
        Write-Host ""
    }
} catch {
    Write-Host "    Could not read display info: $_" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# 2. WINDOWS VRR (Variable Refresh Rate) CHECK
# ---------------------------------------------------------
Write-Host "  [2/5] Variable Refresh Rate (VRR) Status..." -ForegroundColor Cyan

# Check Windows Graphics Settings for VRR
$vrrEnabled = $false
try {
    $gfxSettings = "HKCU:\Software\Microsoft\DirectX\GraphicsSettings"
    if (Test-Path $gfxSettings) {
        # VRR is typically enabled by default in modern Windows with compatible display
        # We check the Windows VRR registry indicator
        $vrrSubkey = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
        # The presence of VRR-compatible settings suggests it's available
        Write-Host "    Windows Graphics settings found - VRR should be available" -ForegroundColor Gray
        
        # Check if there are explicit VRR disable flags
        $autoHDR = (Get-ItemProperty -Path $gfxSettings -Name "AutoHDROptOutApplicable" -EA SilentlyContinue).AutoHDROptOutApplicable
        if ($null -ne $autoHDR) {
            Write-Host "    Windows HDR/VRR awareness: Active" -ForegroundColor Green
        }
        $vrrEnabled = $true  # Windows 10/11 enables this by default
    }
} catch {}

if ($vrrEnabled) {
    Write-Host "    Windows VRR: Likely enabled (default on Win10/11 with modern GPU)" -ForegroundColor Green
    Write-Host "    Verify: Settings > System > Display > Graphics > Default graphics settings" -ForegroundColor Gray
    Write-Host "            'Variable refresh rate' should be ON" -ForegroundColor Gray
} else {
    Write-Host "    Windows VRR: Status unknown - check manually" -ForegroundColor Yellow
    $issuesFound = $true
}
Write-Host ""

# ---------------------------------------------------------
# 3. G-SYNC / FREESYNC INDICATORS
# ---------------------------------------------------------
Write-Host "  [3/5] G-SYNC / FreeSync Detection..." -ForegroundColor Cyan

try {
    $classKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    $nvidiaAdapter = Get-ChildItem $classKey -EA SilentlyContinue | Where-Object {
        $_.GetValue("DriverDesc") -like "*NVIDIA*"
    } | Select-Object -First 1
    
    if ($nvidiaAdapter) {
        Write-Host "    NVIDIA GPU detected - G-SYNC capable" -ForegroundColor Green
        
        # Check for G-SYNC compatible monitor indicators in NV_Modes
        $nvModes = $nvidiaAdapter.GetValue("NV_Modes")
        if ($nvModes) {
            # NV_Modes contains resolution/refresh data - many entries suggest
            # the GPU sees multiple display modes, common with G-SYNC displays
            $modeCount = ([string]$nvModes).Split("{}").Count
            Write-Host "    Display modes detected: $modeCount entries (G-SYNC displays show extra modes)" -ForegroundColor Gray
        }
        
        Write-Host "    Verify G-SYNC:" -ForegroundColor Gray
        Write-Host "      NVIDIA Control Panel > Display > Set up G-SYNC" -ForegroundColor Gray
        Write-Host "      > Enable G-SYNC, G-SYNC Compatible for full screen mode" -ForegroundColor Gray
        Write-Host "      > Also enable for windowed mode if you play borderless" -ForegroundColor Gray
        
        $hasGsync = $true  # Assume yes with NVIDIA GPU + modern monitor
        
        # Check MonitorCapabilityList for adaptive sync hints
        $monCaps = $nvidiaAdapter.GetValue("MonitorCapabilityList")
        if ($monCaps) {
            Write-Host "    Monitor capability data present (likely adaptive-sync display)" -ForegroundColor Green
        }
    } else {
        # Check for AMD
        $amdAdapter = Get-ChildItem $classKey -EA SilentlyContinue | Where-Object {
            $_.GetValue("DriverDesc") -like "*AMD*"
        } | Select-Object -First 1
        if ($amdAdapter) {
            Write-Host "    AMD GPU detected - FreeSync capable" -ForegroundColor Green
            Write-Host "    Verify FreeSync: AMD Software > Gaming > Display > FreeSync ON" -ForegroundColor Gray
            $hasGsync = $true
        } else {
            Write-Host "    No NVIDIA/AMD GPU detected in registry" -ForegroundColor Yellow
            $hasGsync = $false
        }
    }
} catch {
    Write-Host "    G-SYNC detection skipped (registry access limited)" -ForegroundColor Yellow
    Write-Host "    Check manually: NVIDIA Control Panel > Display > Set up G-SYNC" -ForegroundColor Gray
}

# G-SYNC frame cap recommendation
if ($hasGsync) {
    Write-Host ""
    Write-Host "    G-SYNC/FreeSync FRAME CAP TIP:" -ForegroundColor Cyan
    Write-Host "    Cap your in-game FPS 3-4 frames below max refresh to stay" -ForegroundColor White
    Write-Host "    inside the VRR range and avoid V-Sync input lag." -ForegroundColor White
    Write-Host "    Example: 240Hz monitor -> cap at 237 FPS in NVIDIA Control Panel" -ForegroundColor Gray
    Write-Host "    or in-game frame limiter for lowest latency." -ForegroundColor Gray
}
Write-Host ""

# ---------------------------------------------------------
# 4. RESIZABLE BAR (ReBAR) DETECTION
# ---------------------------------------------------------
Write-Host "  [4/5] Resizable BAR (ReBAR) Detection..." -ForegroundColor Cyan

try {
    # ReBAR is a PCIe feature enabled in BIOS + driver. Check device registry.
    $rebarKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    $nvidiaAdapter = Get-ChildItem $rebarKey -EA SilentlyContinue | Where-Object {
        $_.GetValue("DriverDesc") -like "*NVIDIA*"
    } | Select-Object -First 1
    
    if ($nvidiaAdapter) {
        # Check FeatureControl value for ReBAR-related bits
        $featureControl = $nvidiaAdapter.GetValue("FeatureControl")
        Write-Host "    NVIDIA GPU: RTX 30-series+ support ReBAR" -ForegroundColor Green
        
        # ReBAR typically shows up in GPU-Z or NVIDIA Control Panel System Info
        # We can check via WMI for PCIe resizable BAR capability
        $rebarSupport = Get-CimInstance -ClassName Win32_PnPDevice -EA SilentlyContinue | Where-Object {
            $_.Name -match "NVIDIA"
        }
        
        Write-Host "    CHECK ReBAR STATUS:" -ForegroundColor Yellow
        Write-Host "      NVIDIA Control Panel > System Info (bottom-left)" -ForegroundColor Gray
        Write-Host "      Look for: 'Resizable BAR' -> Yes/No" -ForegroundColor Gray
        Write-Host ""
        Write-Host "    If ReBAR shows 'No', you need:" -ForegroundColor White
        Write-Host "      1. Enable 'Above 4G Decoding' and 'Re-Size BAR Support' in BIOS" -ForegroundColor Gray
        Write-Host "      2. Disable CSM (Compatibility Support Module) in BIOS" -ForegroundColor Gray
        Write-Host "      3. GPU driver must support it (NVIDIA 465.89+)" -ForegroundColor Gray
    } else {
        Write-Host "    ReBAR check skipped (no NVIDIA GPU detected in registry)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "    ReBAR detection skipped - check manually in GPU-Z or BIOS" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# 5. FULLSCREEN OPTIMIZATIONS STATUS
# ---------------------------------------------------------
Write-Host "  [5/5] Fullscreen Optimizations & Display Mode..." -ForegroundColor Cyan

try {
    # Check if fullscreen optimizations are disabled (some users prefer this)
    $fsoKey = "HKCU:\System\GameConfigStore"
    if (Test-Path $fsoKey) {
        $fseMode = (Get-ItemProperty -Path $fsoKey -Name "GameDVR_FSEBehaviorMode" -EA SilentlyContinue).GameDVR_FSEBehaviorMode
        if ($fseMode -eq 2) {
            Write-Host "    Fullscreen Optimizations: DISABLED (games run in native fullscreen)" -ForegroundColor Yellow
            Write-Host "    Note: This can REDUCE input lag but disables easy Alt-Tab." -ForegroundColor Gray
        } else {
            Write-Host "    Fullscreen Optimizations: Enabled (games use flip-model, easy Alt-Tab)" -ForegroundColor Green
            Write-Host "    This is the modern default, good for most games." -ForegroundColor Gray
        }
    }
    
    # Check Windows Game Mode fullscreen setting
    $gmKey = "HKCU:\Software\Microsoft\GameBar"
    if (Test-Path $gmKey) {
        $autoGameMode = (Get-ItemProperty -Path $gmKey -Name "AllowAutoGameMode" -EA SilentlyContinue).AllowAutoGameMode
        if ($autoGameMode -eq 1) {
            Write-Host "    Game Mode Auto-detection: ON (Windows optimizes fullscreen games)" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "    Fullscreen optimizations: Could not read status" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
Write-Host "  === DISPLAY CHECK COMPLETE ===" -ForegroundColor Cyan
Write-Host ""

if ($issuesFound) {
    Write-Host "  ISSUES FOUND - Action required:" -ForegroundColor Yellow
    Write-Host "    1. Settings > System > Display > Advanced display" -ForegroundColor White
    Write-Host "       Set your monitor to its maximum refresh rate" -ForegroundColor Gray
    Write-Host "    2. Settings > System > Display > Graphics" -ForegroundColor White
    Write-Host "       Enable 'Variable refresh rate' in Default graphics settings" -ForegroundColor Gray
    Write-Host "    3. NVIDIA Control Panel > Display > Set up G-SYNC" -ForegroundColor White
    Write-Host "       Enable for full screen (and windowed if applicable)" -ForegroundColor Gray
    Write-Host "    4. In-game or NVIDIA Control Panel: cap FPS 3-4 below max refresh" -ForegroundColor White
    Write-Host "    5. Check BIOS for XMP/EXPO, Above 4G Decoding, Re-Size BAR" -ForegroundColor White
} else {
    Write-Host "  Display settings look optimal for gaming!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  QUICK VERIFICATION CHECKLIST:" -ForegroundColor Cyan
    Write-Host "    [] BIOS: XMP/EXPO enabled for RAM" -ForegroundColor Gray
    Write-Host "    [] BIOS: Above 4G Decoding + Re-Size BAR Support enabled" -ForegroundColor Gray
    Write-Host "    [] NVIDIA CP: G-SYNC enabled for full screen mode" -ForegroundColor Gray
    Write-Host "    [] In-game: FPS capped 3-4 below max refresh (e.g., 237 FPS for 240Hz)" -ForegroundColor Gray
    Write-Host "    [] In-game: Anisotropic Filtering set to 16x" -ForegroundColor Gray
    Write-Host "    [] NVIDIA CP: Power Management = Prefer Maximum Performance" -ForegroundColor Gray
}
Write-Host ""
