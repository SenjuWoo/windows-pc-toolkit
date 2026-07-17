<#
.SYNOPSIS
    Enables MSI (Message Signaled Interrupts) mode on GPUs for lower latency.

.DESCRIPTION
    MSI mode replaces legacy line-based interrupts with message-signaled
    interrupts, reducing interrupt latency and CPU overhead. Particularly
    beneficial for high-FPS gaming and VR.

    Applies to all detected NVIDIA and AMD GPUs.

.NOTES
    Requires Administrator privileges. Reboot recommended after enabling.
#>

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "  >> GPU MSI MODE OPTIMIZER" -ForegroundColor Cyan
Write-Host "  Enabling Message Signaled Interrupts for lower latency..." -ForegroundColor Gray
Write-Host ""

$classGuid = "{4d36e968-e325-11ce-bfc1-08002be10318}"
$basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$classGuid"

if (-not (Test-Path $basePath)) {
    Write-Host "  [!] Display adapter class key not found." -ForegroundColor Red
    exit 1
}

$gpuAdapters = Get-ChildItem $basePath -ErrorAction SilentlyContinue | Where-Object {
    ($_.GetValue("DriverDesc") -like "*NVIDIA*") -or
    ($_.GetValue("DriverDesc") -like "*AMD*") -or
    ($_.GetValue("DriverDesc") -like "*Radeon*")
}

if ($gpuAdapters.Count -eq 0) {
    Write-Host "  [!] No NVIDIA or AMD GPU found in registry." -ForegroundColor Yellow
    exit 0
}

$enabled = 0
$alreadySet = 0

foreach ($adapter in $gpuAdapters) {
    $desc = $adapter.GetValue("DriverDesc")
    Write-Host "  Found GPU: $desc" -ForegroundColor White
    Write-Host "    Registry: $($adapter.PSPath)" -ForegroundColor DarkGray

    try {
        # Check if MSI is already enabled
        # MSISupported = 1 means MSI mode is enabled
        # If the value doesn't exist, it uses legacy interrupt mode
        $currentMSI = (Get-ItemProperty -Path $adapter.PSPath -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported

        if ($currentMSI -eq 1) {
            Write-Host "    MSI mode: Already enabled" -ForegroundColor DarkGray
            $alreadySet++
        }
        else {
            # Enable MSI mode
            Set-ItemProperty -Path $adapter.PSPath -Name "MSISupported" -Value 1 -Type DWord -Force -ErrorAction Stop
            Write-Host "    MSI mode: ENABLED (was: $(if($null -eq $currentMSI){'not set'}else{$currentMSI}))" -ForegroundColor Green
            $enabled++
        }

        # Also set interrupt priority to high for GPU
        # MessageNumberLimit = 0 lets the driver choose optimal number of MSI vectors
        $currentMsgLimit = (Get-ItemProperty -Path $adapter.PSPath -Name "MessageNumberLimit" -ErrorAction SilentlyContinue).MessageNumberLimit
        if ($null -eq $currentMsgLimit) {
            Set-ItemProperty -Path $adapter.PSPath -Name "MessageNumberLimit" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "    Message number limit: Set to driver-optimal" -ForegroundColor Green
        }
        else {
            Write-Host "    Message number limit: Already configured ($currentMsgLimit)" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "    [!] Could not set MSI mode: $_" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
Write-Host "  === GPU MSI MODE COMPLETE ===" -ForegroundColor Cyan
Write-Host ""
if ($enabled -gt 0) {
    Write-Host "  MSI mode enabled on $enabled GPU(s)" -ForegroundColor Green
}
if ($alreadySet -gt 0) {
    Write-Host "  MSI mode already active on $alreadySet GPU(s)" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "  MSI mode reduces interrupt latency by replacing legacy IRQ lines" -ForegroundColor Gray
Write-Host "  with high-priority message-based interrupts." -ForegroundColor Gray
Write-Host ""
Write-Host "  REBOOT RECOMMENDED for MSI mode to take full effect." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Verify with: Device Manager > GPU > Properties > Resources tab" -ForegroundColor DarkGray
Write-Host "  (Look for 'Message Signaled Interrupts' instead of IRQ)" -ForegroundColor DarkGray