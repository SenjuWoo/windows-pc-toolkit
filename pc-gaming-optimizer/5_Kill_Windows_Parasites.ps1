<#
.SYNOPSIS
    Kills Windows "parasites" - telemetry, bloat, background cruft.
    PRESERVES Windows Update functionality (DoSvc, telemetry policy level 1).

.DESCRIPTION
    Disables data-collection services, bloat, Cortana, Widgets, tips/ads,
    and clears RAM standby list - WITHOUT breaking Windows Update or DISM.

    IMPORTANT: This script intentionally keeps DoSvc (Delivery Optimization)
    and telemetry at level 1 (Required) to avoid breaking Windows Update,
    Store, and DISM /RestoreHealth (error 0x800f0915).

.NOTES
    Requires Administrator privileges. Some changes require reboot.
#>

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "  >> KILLING WINDOWS PARASITES" -ForegroundColor Cyan
Write-Host "  Disabling telemetry, bloat, and background cruft..." -ForegroundColor Gray
Write-Host "  (Preserving Windows Update / DISM compatibility)" -ForegroundColor DarkGray
Write-Host ""

$needsReboot = $false

# ---------------------------------------------------------
# 1. CONNECTED USER EXPERIENCES AND TELEMETRY (DiagTrack)
# ---------------------------------------------------------
Write-Host "  [1/10] Disabling Connected User Experiences and Telemetry (DiagTrack)..." -ForegroundColor Cyan
$diagTrackKey = "HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack"
if (Test-Path $diagTrackKey) {
    $current = (Get-ItemProperty -Path $diagTrackKey -Name "Start" -ErrorAction SilentlyContinue).Start
    if ($current -ne 4) {
        Set-ItemProperty -Path $diagTrackKey -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "    DiagTrack service disabled (was: $current)" -ForegroundColor Green
        $needsReboot = $true
    } else {
        Write-Host "    DiagTrack already disabled" -ForegroundColor DarkGray
    }
    $svc = Get-Service -Name "DiagTrack" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
        Write-Host "    Stopped DiagTrack immediately" -ForegroundColor Green
    }
} else {
    Write-Host "    DiagTrack service not found" -ForegroundColor DarkGray
}

# Set telemetry to level 1 (Required diagnostics only) - NOT level 0!
# Level 0 breaks Windows Update health checks and DISM. Level 1 is safe.
$telPolKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
if (-not (Test-Path $telPolKey)) { New-Item -Path $telPolKey -Force | Out-Null }
Set-ItemProperty -Path $telPolKey -Name "AllowTelemetry" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Telemetry policy: Level 1 (Required diagnostics only - WU safe)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 2. DELIVERY OPTIMIZATION - KEEP ENABLED (Required by WU!)
# ---------------------------------------------------------
Write-Host "  [2/10] Delivery Optimization..." -ForegroundColor Cyan
Write-Host "    DoSvc KEPT ENABLED - required by Windows Update and DISM" -ForegroundColor Yellow
Write-Host "    (Disabling DoSvc causes update failures and DISM 0x800f0915)" -ForegroundColor DarkGray

# Only restrict P2P sharing, don't disable the service itself
$deliveryOptKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
if (-not (Test-Path $deliveryOptKey)) {
    New-Item -Path $deliveryOptKey -Force | Out-Null
}
# DownloadMode 0 = HTTP only (no P2P), but service stays running
Set-ItemProperty -Path $deliveryOptKey -Name "DODownloadMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    P2P sharing disabled (HTTP-only downloads)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 3. CLEAR RAM STANDBY LIST
# ---------------------------------------------------------
Write-Host "  [3/10] Clearing RAM standby list (cached memory)..." -ForegroundColor Cyan
try {
    # Same NtSetSystemInformation mechanism as 8_Free_RAM.ps1 / Sysinternals RAMMap
    $purgeSource = @'
using System;
using System.Runtime.InteropServices;
public static class StandbyListPurge
{
    [StructLayout(LayoutKind.Sequential)]
    public struct TokPriv1Luid { public int Count; public long Luid; public int Attr; }

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("ntdll.dll")]
    public static extern uint NtSetSystemInformation(int infoClass, ref int info, int length);

    public static uint Purge()
    {
        IntPtr tok = IntPtr.Zero;
        TokPriv1Luid tp;
        tp.Count = 1;
        tp.Luid = 0;
        tp.Attr = 2; // SE_PRIVILEGE_ENABLED
        OpenProcessToken(GetCurrentProcess(), 32 | 8, ref tok);
        LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", ref tp.Luid);
        AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        int cmd = 5; // MemoryPurgeLowPriorityStandbyList
        NtSetSystemInformation(80, ref cmd, 4);
        cmd = 4;     // MemoryPurgeStandbyList
        return NtSetSystemInformation(80, ref cmd, 4);
    }
}
'@
    if (-not ("StandbyListPurge" -as [type])) {
        Add-Type -TypeDefinition $purgeSource -ErrorAction Stop
    }
    $status = [StandbyListPurge]::Purge()
    if ($status -eq 0) {
        Write-Host "    Standby list purged - cached memory released" -ForegroundColor Green
    } else {
        Write-Host "    Purge returned NTSTATUS $status (needs Admin)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "    Could not purge standby list: $_" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# 4. ADDITIONAL BLOAT / TRACKING SERVICES
# ---------------------------------------------------------
Write-Host "  [4/10] Disabling additional bloat and tracking services..." -ForegroundColor Cyan

$bloatServices = @(
    @{ Name = "dmwappushservice";  Desc = "WAP Push Message Routing" },
    @{ Name = "RetailDemo";        Desc = "Retail Demo Service" },
    @{ Name = "WpcMonSvc";         Desc = "Parental Controls" },
    @{ Name = "wisvc";             Desc = "Windows Insider Service" },
    @{ Name = "MapsBroker";        Desc = "Downloaded Maps Manager" },
    @{ Name = "lfsvc";             Desc = "Geolocation Service" },
    @{ Name = "SharedAccess";      Desc = "Internet Connection Sharing" },
    @{ Name = "RemoteRegistry";    Desc = "Remote Registry" },
    @{ Name = "CopilotSvc";        Desc = "Windows Copilot Service" },
    @{ Name = "SEMgrSvc";          Desc = "NFC/SE Payments and SIM manager" }
)

foreach ($svcInfo in $bloatServices) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svcInfo.Name)"
    if (Test-Path $key) {
        $current = (Get-ItemProperty -Path $key -Name "Start" -ErrorAction SilentlyContinue).Start
        if ($current -ne 4) {
            Set-ItemProperty -Path $key -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "    Disabled: $($svcInfo.Desc)" -ForegroundColor Green
            $needsReboot = $true
        }
    }
}

# Services to set to Manual (demand) instead of Disabled - safer for system health
$manualServices = @(
    @{ Name = "TrkWks";    Desc = "Distributed Link Tracking" },
    @{ Name = "WerSvc";    Desc = "Windows Error Reporting" },
    @{ Name = "DiagSvcs";  Desc = "Diagnostic Service Host" }
)
foreach ($svcInfo in $manualServices) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svcInfo.Name)"
    if (Test-Path $key) {
        $current = (Get-ItemProperty -Path $key -Name "Start" -ErrorAction SilentlyContinue).Start
        if ($current -ne 3) {
            Set-ItemProperty -Path $key -Name "Start" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "    Set to Manual: $($svcInfo.Desc)" -ForegroundColor Green
        }
    }
}
Write-Host ""

# ---------------------------------------------------------
# 5. DISABLE BLOAT SCHEDULED TASKS
# ---------------------------------------------------------
Write-Host "  [5/10] Disabling bloat scheduled tasks..." -ForegroundColor Cyan

$bloatTasks = @(
    "\Microsoft\Windows\Customer Experience Improvement Program\*",
    "\Microsoft\Windows\Autochk\Proxy",
    "\Microsoft\Windows\DiskDiagnostic\*",
    "\Microsoft\Windows\PI\Sqm-Tasks",
    "\Microsoft\Windows\DiskFootprint\Diagnostics",
    "\Microsoft\Windows\Feedback\*",
    "\Microsoft\Windows\Windows Copilot\*",
    "\Microsoft\Windows\Management\Provisioning\*"
)

foreach ($taskPath in $bloatTasks) {
    try {
        Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.State -ne "Disabled") {
                Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue | Out-Null
                Write-Host "    Disabled: $($_.TaskName)" -ForegroundColor Green
            }
        }
    } catch { }
}

# KEEP Application Experience tasks enabled (needed for feature updates!)
Write-Host "    Application Experience tasks: KEPT ENABLED (required for feature updates)" -ForegroundColor Yellow
Write-Host ""

# ---------------------------------------------------------
# 6. CORTANA, WEB SEARCH, NEWS & WIDGETS
# ---------------------------------------------------------
Write-Host "  [6/10] Nuking Cortana, web search, News & Widgets..." -ForegroundColor Cyan

$cortKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
if (-not (Test-Path $cortKey)) { New-Item -Path $cortKey -Force | Out-Null }
Set-ItemProperty -Path $cortKey -Name "AllowCortana" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cortKey -Name "DisableWebSearch" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cortKey -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
# BingSearchEnabled lives under the per-user Search key (not the policy key)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Cortana + Bing web search: DISABLED" -ForegroundColor Green

# Windows Copilot (Win11) - background AI assistant, taskbar button
$copilotPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
if (-not (Test-Path $copilotPol)) { New-Item -Path $copilotPol -Force | Out-Null }
Set-ItemProperty -Path $copilotPol -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
$copilotPolUser = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
if (-not (Test-Path $copilotPolUser)) { New-Item -Path $copilotPolUser -Force | Out-Null }
Set-ItemProperty -Path $copilotPolUser -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Windows Copilot: DISABLED" -ForegroundColor Green

# Recall (Win11 24H2 Copilot+ PCs) - AI screenshot/timeline feature, massive perf hog
$recallPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
if (-not (Test-Path $recallPol)) { New-Item -Path $recallPol -Force | Out-Null }
Set-ItemProperty -Path $recallPol -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $recallPol -Name "AllowRecallEnablement" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $recallPol -Name "TurnOffWindowsAI" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
$recallPolUser = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
if (-not (Test-Path $recallPolUser)) { New-Item -Path $recallPolUser -Force | Out-Null }
Set-ItemProperty -Path $recallPolUser -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $recallPolUser -Name "AllowRecallEnablement" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $recallPolUser -Name "TurnOffWindowsAI" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Recall + Windows AI features: DISABLED (screenshots, AI data analysis, AI in Paint/Photos)" -ForegroundColor Green

# Copilot in Microsoft 365 / Office apps
$officeCopilotPol = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate"
if (-not (Test-Path $officeCopilotPol)) { New-Item -Path $officeCopilotPol -Force | Out-Null }
Set-ItemProperty -Path $officeCopilotPol -Name "disablecsi" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Microsoft 365 Copilot integration: BLOCKED" -ForegroundColor Green

# AI-powered web results in Windows Search
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings")) { New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Force | Out-Null }
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsAADCloudSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsDeviceSearchHistoryEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    AI-powered web search in Windows: DISABLED" -ForegroundColor Green

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    News & Interests: DISABLED" -ForegroundColor Green

$widgKey = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
if (-not (Test-Path $widgKey)) { New-Item -Path $widgKey -Force | Out-Null }
Set-ItemProperty -Path $widgKey -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Widgets: DISABLED" -ForegroundColor Green

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Taskbar clutter: Hidden (search box + task view)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 7. XBOX LIVE SERVICES - Keep enabled for PC gaming
# ---------------------------------------------------------
Write-Host "  [7/10] Xbox Live services..." -ForegroundColor Cyan
Write-Host "    Xbox services: KEPT ENABLED (needed for Game Bar, PC Game Pass, Xbox networking)" -ForegroundColor Yellow
Write-Host "    (Game DVR recording already handled by Gaming Optimizer script)" -ForegroundColor DarkGray
Write-Host ""

# ---------------------------------------------------------
# 8. TIPS, TRICKS & SUGGESTED CONTENT
# ---------------------------------------------------------
Write-Host "  [8/10] Killing tips, tricks, and suggested content..." -ForegroundColor Cyan
$cdmKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Set-ItemProperty -Path $cdmKey -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cdmKey -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cdmKey -Name "PreInstalledAppsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cdmKey -Name "OemPreInstalledAppsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cdmKey -Name "SoftLandingEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cdmKey -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cdmKey -Name "SubscribedContent-338393Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Tips, tricks, suggested content, Start ads: ALL OFF" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 9. MICROSOFT EDGE / BROWSER TELEMETRY + COPILOT
# ---------------------------------------------------------
Write-Host "  [9/10] Disabling browser AI telemetry and Copilot integration..." -ForegroundColor Cyan
$edgeKey = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $edgeKey)) { New-Item -Path $edgeKey -Force | Out-Null }
Set-ItemProperty -Path $edgeKey -Name "EdgeEnhanceImagesEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $edgeKey -Name "HubsSidebarEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $edgeKey -Name "SpotlightExperiencesAndRecommendationsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $edgeKey -Name "CopilotPageContext" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $edgeKey -Name "CopilotCDPPageContext" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $edgeKey -Name "AIGenThemesEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $edgeKey -Name "AskCopilotEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Edge sidebar, spotlight, Copilot, AI themes: ALL DISABLED" -ForegroundColor Green

# Block Copilot in Chrome policies (if Chrome is installed, these get honored)
$chromeKey = "HKLM:\SOFTWARE\Policies\Google\Chrome"
if (-not (Test-Path $chromeKey)) { New-Item -Path $chromeKey -Force | Out-Null }
Set-ItemProperty -Path $chromeKey -Name "GenAILocalFoundationalModelSettings" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Chrome AI/genAI features: BLOCKED" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 10. REMOVE COPILOT APP PACKAGE
# ---------------------------------------------------------
Write-Host "  [10/10] Removing Windows Copilot AppX package..." -ForegroundColor Cyan
$copilotApps = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like "*Microsoft.Copilot*" -or $_.Name -like "*Microsoft.WindowsAi*"
})
if ($copilotApps.Count -gt 0) {
    foreach ($app in $copilotApps) {
        try {
            Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
            Write-Host "    Removed: $($app.Name)" -ForegroundColor Green
        } catch {
            Write-Host "    Could not remove $($app.Name) (may be a system package): $_" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "    No standalone Copilot/AI apps found (already removed or not installed)" -ForegroundColor DarkGray
}
Write-Host ""

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
Write-Host "  === PARASITE CLEANUP COMPLETE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Disabled / Killed:" -ForegroundColor White
Write-Host "    - Connected User Experiences & Telemetry (DiagTrack)" -ForegroundColor Green
Write-Host "    - Delivery Optimization P2P sharing (HTTP-only, service preserved)" -ForegroundColor Green
Write-Host "    - 10+ bloat / tracking services (incl. CopilotSvc)" -ForegroundColor Green
Write-Host "    - Cortana + Bing web search + News & Widgets + Copilot" -ForegroundColor Green
Write-Host "    - Windows Recall + AI features (screenshots, Paint/Photos AI, data analysis)" -ForegroundColor Green
Write-Host "    - Microsoft 365 Copilot integration" -ForegroundColor Green
Write-Host "    - Copilot AppX package removed" -ForegroundColor Green
Write-Host "    - RAM standby list cleared" -ForegroundColor Green
Write-Host "    - Tips, tricks, suggested content, Start ads" -ForegroundColor Green
Write-Host "    - Edge Copilot sidebar, page context, AI themes + Chrome AI" -ForegroundColor Green
Write-Host "    - Bloat scheduled tasks (CEIP, diagnostics, Copilot)" -ForegroundColor Green
Write-Host ""
Write-Host "  Preserved (by design):" -ForegroundColor White
Write-Host "    - DoSvc (Delivery Optimization) - REQUIRED by Windows Update / DISM" -ForegroundColor Yellow
Write-Host "    - Telemetry policy level 1 (Required) - level 0 breaks WU health checks" -ForegroundColor Yellow
Write-Host "    - Application Experience tasks - REQUIRED for feature updates" -ForegroundColor Yellow
Write-Host "    - Xbox Live services - REQUIRED for Game Bar, PC Game Pass, Xbox networking" -ForegroundColor Yellow
Write-Host ""

if ($needsReboot) {
    Write-Host "  REBOOT REQUIRED for service changes to take full effect." -ForegroundColor Yellow
} else {
    Write-Host "  No reboot strictly required, but recommended." -ForegroundColor Gray
}