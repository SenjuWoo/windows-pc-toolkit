<#
.SYNOPSIS
    FIX WINDOWS UPDATE - repairs everything an "optimizer" (including old
    versions of this one) may have broken, without re-enabling telemetry junk.

.DESCRIPTION
    Older versions of this optimizer disabled DoSvc (Delivery Optimization).
    On Windows 10/11, DoSvc is the downloader for Windows Update, the Store,
    and DISM repair content. Disabling it causes update failures and DISM
    errors like 0x800f0915 ("The repair content could not be found").

    This script:
      1. Restores all Windows Update services to factory defaults
      2. Re-enables the Compatibility Appraiser tasks (needed for feature updates)
      3. Removes registry policies that block updates
      4. (Optional) Resets the Windows Update cache (SoftwareDistribution/catroot2)
      5. (Optional) Runs DISM /RestoreHealth + SFC /scannow
      6. Triggers a fresh update scan

    It does NOT re-enable DiagTrack telemetry, Cortana, ads, or P2P sharing.

.NOTES
    Requires Administrator privileges. Reboot afterwards, then check
    Settings > Windows Update.
#>

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "  >> FIX WINDOWS UPDATE" -ForegroundColor Cyan
Write-Host "  Restores everything Windows Update needs - keeps telemetry/ads OFF." -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------
# 1. RESTORE UPDATE SERVICES TO FACTORY DEFAULTS
# ---------------------------------------------------------
Write-Host "  [1/6] Restoring Windows Update services to factory defaults..." -ForegroundColor Cyan

# mode strings for sc.exe; regStart is the fallback registry value
$updateServices = @(
    @{ Name = "wuauserv";         Mode = "demand";       RegStart = 3; Desc = "Windows Update" },
    @{ Name = "BITS";             Mode = "demand";       RegStart = 3; Desc = "Background Intelligent Transfer" },
    @{ Name = "cryptsvc";         Mode = "auto";         RegStart = 2; Desc = "Cryptographic Services" },
    @{ Name = "TrustedInstaller"; Mode = "demand";       RegStart = 3; Desc = "Windows Modules Installer" },
    @{ Name = "DoSvc";            Mode = "delayed-auto"; RegStart = 2; Desc = "Delivery Optimization (REQUIRED by WU)" },
    @{ Name = "UsoSvc";           Mode = "delayed-auto"; RegStart = 2; Desc = "Update Orchestrator" },
    @{ Name = "WaaSMedicSvc";     Mode = "demand";       RegStart = 3; Desc = "Windows Update Medic" },
    @{ Name = "msiserver";        Mode = "demand";       RegStart = 3; Desc = "Windows Installer" }
)

foreach ($s in $updateServices) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)"
    if (-not (Test-Path $key)) {
        Write-Host "  [ -- ] $($s.Name) not found, skipping" -ForegroundColor DarkGray
        continue
    }
    $before = (Get-ItemProperty -Path $key -Name "Start" -ErrorAction SilentlyContinue).Start
    sc.exe config $s.Name start= $s.Mode | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # Some services (e.g. WaaSMedicSvc) refuse sc.exe - write the registry directly
        try {
            Set-ItemProperty -Path $key -Name "Start" -Value $s.RegStart -Type DWord -Force -ErrorAction Stop
            if ($s.Mode -eq "delayed-auto") {
                Set-ItemProperty -Path $key -Name "DelayedAutostart" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Host "  [WARN] Could not reconfigure $($s.Name): $_" -ForegroundColor Yellow
            continue
        }
    }
    if ($before -eq 4) {
        Write-Host "  [ OK ] $($s.Desc) ($($s.Name)) - WAS DISABLED, now restored!" -ForegroundColor Yellow
    } else {
        Write-Host "  [ OK ] $($s.Desc) ($($s.Name)) - default startup restored" -ForegroundColor Green
    }
}
Write-Host ""

# ---------------------------------------------------------
# 2. RE-ENABLE UPDATE-RELATED SCHEDULED TASKS
# ---------------------------------------------------------
Write-Host "  [2/6] Re-enabling Compatibility Appraiser tasks (feature updates need these)..." -ForegroundColor Cyan
try {
    $appExpTasks = @(Get-ScheduledTask -TaskPath "\Microsoft\Windows\Application Experience\" -ErrorAction SilentlyContinue)
    $fixed = 0
    foreach ($t in $appExpTasks) {
        if ($t.State -eq "Disabled") {
            Enable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  [ OK ] Re-enabled: $($t.TaskName)" -ForegroundColor Green
            $fixed++
        }
    }
    if ($fixed -eq 0) { Write-Host "  [ OK ] All Application Experience tasks already enabled" -ForegroundColor Green }
}
catch {
    Write-Host "  [WARN] Could not check scheduled tasks: $_" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# 3. REMOVE POLICIES THAT BLOCK UPDATES
# ---------------------------------------------------------
Write-Host "  [3/6] Removing registry policies that can block updates..." -ForegroundColor Cyan

$wuPolKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$blockValues = @("DoNotConnectToWindowsUpdateInternetLocations", "DisableWindowsUpdateAccess", "SetDisableUXWUAccess")
$removedAny = $false
if (Test-Path $wuPolKey) {
    foreach ($v in $blockValues) {
        $exists = Get-ItemProperty -Path $wuPolKey -Name $v -ErrorAction SilentlyContinue
        if ($null -ne $exists) {
            Remove-ItemProperty -Path $wuPolKey -Name $v -Force -ErrorAction SilentlyContinue
            Write-Host "  [ OK ] Removed blocking policy: $v" -ForegroundColor Green
            $removedAny = $true
        }
    }
    $auKey = "$wuPolKey\AU"
    if (Test-Path $auKey) {
        $noAuto = (Get-ItemProperty -Path $auKey -Name "NoAutoUpdate" -ErrorAction SilentlyContinue).NoAutoUpdate
        if ($noAuto -eq 1) {
            Remove-ItemProperty -Path $auKey -Name "NoAutoUpdate" -Force -ErrorAction SilentlyContinue
            Write-Host "  [ OK ] Removed policy: NoAutoUpdate" -ForegroundColor Green
            $removedAny = $true
        }
    }
}

# Telemetry policy 0 can confuse update health checks on some builds - raise to 1 (Required only)
$telPolKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
if (Test-Path $telPolKey) {
    $tel = (Get-ItemProperty -Path $telPolKey -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
    if ($tel -eq 0) {
        Set-ItemProperty -Path $telPolKey -Name "AllowTelemetry" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  [ OK ] AllowTelemetry raised from 0 to 1 (Required diagnostics only)" -ForegroundColor Green
        $removedAny = $true
    }
}
if (-not $removedAny) { Write-Host "  [ OK ] No blocking policies found" -ForegroundColor Green }
Write-Host ""

# ---------------------------------------------------------
# 4. OPTIONAL: RESET WINDOWS UPDATE CACHE
# ---------------------------------------------------------
Write-Host "  [4/6] Reset Windows Update cache (SoftwareDistribution + catroot2)?" -ForegroundColor Cyan
Write-Host "        Recommended if updates keep failing after the service fix." -ForegroundColor Gray
$doReset = Read-Host "        Reset now? (y/N)"
if ($doReset -eq "y" -or $doReset -eq "Y") {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    Write-Host "  Stopping update services..." -ForegroundColor Gray
    foreach ($svc in @("wuauserv","BITS","cryptsvc","msiserver")) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2

    $sd = Join-Path $env:SystemRoot "SoftwareDistribution"
    if (Test-Path $sd) {
        try {
            Rename-Item -Path $sd -NewName "SoftwareDistribution.bak_$ts" -ErrorAction Stop
            Write-Host "  [ OK ] SoftwareDistribution renamed (Windows rebuilds it automatically)" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Could not rename SoftwareDistribution (in use). Reboot and run this again." -ForegroundColor Yellow
        }
    }

    $cr2 = Join-Path $env:SystemRoot "System32\catroot2"
    if (Test-Path $cr2) {
        try {
            Rename-Item -Path $cr2 -NewName "catroot2.bak_$ts" -ErrorAction Stop
            Write-Host "  [ OK ] catroot2 renamed" -ForegroundColor Green
        } catch {
            Write-Host "  [ -- ] catroot2 in use - skipped (usually not needed; SoftwareDistribution reset is the main fix)" -ForegroundColor DarkGray
        }
    }

    Start-Service -Name "cryptsvc" -ErrorAction SilentlyContinue
    Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    Write-Host "  [ OK ] Update services restarted" -ForegroundColor Green
} else {
    Write-Host "  [ -- ] Skipped" -ForegroundColor DarkGray
}
Write-Host ""

# ---------------------------------------------------------
# 5. OPTIONAL: REPAIR SYSTEM IMAGE (DISM + SFC)
# ---------------------------------------------------------
Write-Host "  [5/6] Repair the Windows image now? (DISM /RestoreHealth + SFC /scannow)" -ForegroundColor Cyan
Write-Host "        Do this if you saw DISM error 0x800f0915. Takes 10-30 minutes." -ForegroundColor Gray
Write-Host "        NOTE: run this AFTER the services above are fixed - DISM downloads" -ForegroundColor Gray
Write-Host "        its repair content through Windows Update / Delivery Optimization." -ForegroundColor Gray
$doRepair = Read-Host "        Run repair now? (y/N)"
if ($doRepair -eq "y" -or $doRepair -eq "Y") {
    Write-Host ""
    Write-Host "  Running DISM /Online /Cleanup-Image /RestoreHealth ..." -ForegroundColor Yellow
    & "$env:SystemRoot\System32\Dism.exe" /Online /Cleanup-Image /RestoreHealth
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [ OK ] DISM RestoreHealth completed successfully" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] DISM exited with code $LASTEXITCODE." -ForegroundColor Yellow
        Write-Host "         If it still fails: reboot first (service changes need it), then retry." -ForegroundColor Yellow
        Write-Host "         Last resort: in-place repair install from a Windows 11 ISO" -ForegroundColor Yellow
        Write-Host "         (setup.exe > Keep personal files and apps)." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Running SFC /scannow ..." -ForegroundColor Yellow
    & "$env:SystemRoot\System32\sfc.exe" /scannow
    Write-Host ""
} else {
    Write-Host "  [ -- ] Skipped (you can rerun this script anytime)" -ForegroundColor DarkGray
}
Write-Host ""

# ---------------------------------------------------------
# 6. TRIGGER A FRESH UPDATE SCAN
# ---------------------------------------------------------
Write-Host "  [6/6] Triggering a fresh Windows Update scan..." -ForegroundColor Cyan
Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
try {
    & "$env:SystemRoot\System32\UsoClient.exe" StartInteractiveScan 2>$null
    Write-Host "  [ OK ] Update scan requested" -ForegroundColor Green
} catch {
    Write-Host "  [ -- ] Could not trigger scan automatically" -ForegroundColor DarkGray
}
Write-Host ""

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
Write-Host "  === WINDOWS UPDATE REPAIR COMPLETE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "   1. REBOOT your PC (service changes need it)" -ForegroundColor Yellow
Write-Host "   2. Open Settings > Windows Update > Check for updates" -ForegroundColor White
Write-Host "   3. If DISM previously failed with 0x800f0915, rerun:" -ForegroundColor White
Write-Host "        DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor Gray
Write-Host ""
Write-Host "  Still OFF (by design): DiagTrack telemetry, Cortana, ads, P2P sharing." -ForegroundColor Gray
