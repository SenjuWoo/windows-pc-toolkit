<#
.SYNOPSIS
    UNDO ALL - restores Windows factory defaults for every setting this
    optimizer changes (any version, old or new).

.DESCRIPTION
    Reverts: services, scheduled tasks, telemetry/search/widget/Copilot/Recall
    policies, gaming tweaks (GameDVR, HAGS, MMCSS, CPU scheduling, mouse
    acceleration, accessibility hotkeys, keyboard delay), visual effects,
    network tweaks, Delivery Optimization config, NVIDIA registry values,
    SSD/NTFS tweaks, MSI mode, timer/BCD/global timer requests, power plan,
    Edge/Chrome browser policies, Office Copilot integration, AI search settings.

    Does not restore deleted shader caches (they rebuild automatically).

.NOTES
    Requires Administrator privileges. Reboot afterwards.
#>

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "  >> UNDO ALL OPTIMIZATIONS" -ForegroundColor Cyan
Write-Host "  This restores Windows defaults for everything this optimizer changed." -ForegroundColor Gray
Write-Host ""
$confirm = Read-Host "  Type YES to continue"
if ($confirm -ne "YES") {
    Write-Host "  Cancelled - nothing was changed." -ForegroundColor Yellow
    exit 0
}
Write-Host ""

# ---------------------------------------------------------
# 1. SERVICES: back to factory startup types
# ---------------------------------------------------------
Write-Host "  [1/11] Restoring service startup defaults..." -ForegroundColor Cyan
$svcDefaults = @(
    @{ Name = "DiagTrack";        Mode = "auto" },
    @{ Name = "dmwappushservice"; Mode = "demand" },
    @{ Name = "SysMain";          Mode = "auto" },
    @{ Name = "XblAuthManager";   Mode = "demand" },
    @{ Name = "XblGameSave";      Mode = "demand" },
    @{ Name = "XboxGipSvc";       Mode = "demand" },
    @{ Name = "XboxNetApiSvc";    Mode = "demand" },
    @{ Name = "RetailDemo";       Mode = "demand" },
    @{ Name = "WpcMonSvc";        Mode = "demand" },
    @{ Name = "wisvc";            Mode = "demand" },
    @{ Name = "MapsBroker";       Mode = "delayed-auto" },
    @{ Name = "lfsvc";            Mode = "demand" },
    @{ Name = "SharedAccess";     Mode = "demand" },
    @{ Name = "RemoteRegistry";   Mode = "demand" },
    @{ Name = "CopilotSvc";       Mode = "demand" },
    @{ Name = "SEMgrSvc";         Mode = "demand" },
    @{ Name = "TrkWks";           Mode = "auto" },
    @{ Name = "WerSvc";           Mode = "demand" },
    @{ Name = "DiagSvcs";         Mode = "demand" }
)
foreach ($s in $svcDefaults) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)"
    if (Test-Path $key) {
        sc.exe config $s.Name start= $s.Mode | Out-Null
        Write-Host "  [ OK ] $($s.Name) -> $($s.Mode)" -ForegroundColor Green
    }
}
Write-Host ""

# ---------------------------------------------------------
# 2. SCHEDULED TASKS: re-enable everything we disabled
# ---------------------------------------------------------
Write-Host "  [2/11] Re-enabling scheduled tasks..." -ForegroundColor Cyan
$taskFolders = @(
    "\Microsoft\Windows\Customer Experience Improvement Program\",
    "\Microsoft\Windows\Application Experience\",
    "\Microsoft\Windows\Autochk\",
    "\Microsoft\Windows\DiskDiagnostic\",
    "\Microsoft\Windows\PI\",
    "\Microsoft\Windows\DiskFootprint\",
    "\Microsoft\Windows\Feedback\",
    "\Microsoft\Windows\Windows Copilot\",
    "\Microsoft\Windows\Management\Provisioning\"
)
foreach ($folder in $taskFolders) {
    try {
        Get-ScheduledTask -TaskPath $folder -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.State -eq "Disabled") {
                Enable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue | Out-Null
                Write-Host "  [ OK ] Re-enabled: $($_.TaskName)" -ForegroundColor Green
            }
        }
    } catch { }
}
Write-Host ""

# ---------------------------------------------------------
# 3. POLICIES: telemetry, search, widgets, feeds, Edge
# ---------------------------------------------------------
Write-Host "  [3/11] Removing policy overrides..." -ForegroundColor Cyan
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Force -ErrorAction SilentlyContinue
$searchPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
if (Test-Path $searchPol) {
    foreach ($v in @("AllowCortana","DisableWebSearch","ConnectedSearchUseWeb","BingSearchEnabled")) {
        Remove-ItemProperty -Path $searchPol -Name $v -Force -ErrorAction SilentlyContinue
    }
}
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

# Edge policies
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "EdgeEnhanceImagesEnabled" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HubsSidebarEnabled" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "SpotlightExperiencesAndRecommendationsEnabled" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "CopilotPageContext" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "CopilotCDPPageContext" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "AIGenThemesEnabled" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "AskCopilotEnabled" -Force -ErrorAction SilentlyContinue

# Chrome AI policies
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "GenAILocalFoundationalModelSettings" -Force -ErrorAction SilentlyContinue

# Windows Copilot policies
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Force -ErrorAction SilentlyContinue

# Windows Recall / AI policies
foreach ($v in @("DisableAIDataAnalysis","AllowRecallEnablement","TurnOffWindowsAI")) {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name $v -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name $v -Force -ErrorAction SilentlyContinue
}

# Microsoft 365 Copilot policy
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate" -Name "disablecsi" -Force -ErrorAction SilentlyContinue

# AI-powered search policies
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsAADCloudSearchEnabled" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsDeviceSearchHistoryEnabled" -Force -ErrorAction SilentlyContinue

Write-Host "  [ OK ] Cortana / web search / widgets / feeds / Edge / Copilot policies removed" -ForegroundColor Green

# Tips & suggested content back to defaults
$cdmKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
foreach ($v in @("SystemPaneSuggestionsEnabled","SilentInstalledAppsEnabled","PreInstalledAppsEnabled","OemPreInstalledAppsEnabled","SoftLandingEnabled","SubscribedContent-338389Enabled","SubscribedContent-338393Enabled")) {
    Set-ItemProperty -Path $cdmKey -Name $v -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "  [ OK ] Tips / suggestions restored to defaults" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 4. GAMING TWEAKS: back to defaults
# ---------------------------------------------------------
Write-Host "  [4/11] Restoring gaming tweaks to defaults..." -ForegroundColor Cyan

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_HonorUserFSEBehaviorMode" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Force -ErrorAction SilentlyContinue

# HAGS
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode2" -Force -ErrorAction SilentlyContinue

# Power throttling
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Force -ErrorAction SilentlyContinue

# MMCSS Games profile defaults
$mmcssKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
if (Test-Path $mmcssKey) {
    Set-ItemProperty -Path $mmcssKey -Name "GPU Priority"        -Value 8        -Type DWord  -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssKey -Name "Priority"            -Value 2        -Type DWord  -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssKey -Name "Scheduling Category" -Value "Medium" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssKey -Name "SFIO Priority"       -Value "Normal" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mmcssKey -Name "Background Only"     -Value "True"   -Type String -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $mmcssKey -Name "Clock Rate" -Force -ErrorAction SilentlyContinue
}

# CPU scheduling default
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

# Mouse acceleration back on (Windows default) - registry + immediate apply
Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed"      -Value "1"  -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "6"  -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "10" -Force -ErrorAction SilentlyContinue
try {
    $spiSource = @'
using System;
using System.Runtime.InteropServices;
public static class MouseParams
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);

    public static bool SetAcceleration(int on)
    {
        int[] mouseParams = new int[] { 6, 10, on };
        return SystemParametersInfo(0x0004, 0, mouseParams, 0x03);
    }
}
'@
    if (-not ("MouseParams" -as [type])) { Add-Type -TypeDefinition $spiSource -ErrorAction Stop }
    [MouseParams]::SetAcceleration(1) | Out-Null
} catch { }

# Accessibility hotkeys back to Windows defaults (Sticky/Toggle/Filter Keys)
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\StickyKeys"        -Name "Flags" -Value "510" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\ToggleKeys"        -Name "Flags" -Value "62"  -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "Flags" -Value "126" -Force -ErrorAction SilentlyContinue

# Keyboard repeat delay default
Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "1" -Force -ErrorAction SilentlyContinue

# Background apps back on
$bgKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
if (Test-Path $bgKey) {
    Get-ChildItem $bgKey -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-ItemProperty -Path $_.PSPath -Name "Disabled" -Force -ErrorAction SilentlyContinue
    }
}

# Focus Assist back to defaults
$focusKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
Remove-ItemProperty -Path $focusKey -Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $focusKey -Name "NOC_GLOBAL_SETTING_ALLOW_CALLS"    -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $focusKey -Name "NOC_GLOBAL_SETTING_SUPPRESS_ALL"   -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\QuietHours" -Name "Enable" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\QuietHours" -Name "Enable" -Force -ErrorAction SilentlyContinue

Write-Host "  [ OK ] GameDVR, HAGS, MMCSS, CPU scheduling, mouse, background apps, Focus Assist -> defaults" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 5. VISUAL EFFECTS: let Windows choose
# ---------------------------------------------------------
Write-Host "  [5/11] Restoring visual effects to Windows defaults..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value ([byte[]](0x9E,0x3E,0x07,0x80,0x12,0x00,0x00,0x00)) -Type Binary -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "400" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "AutoEndTasks" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -Force -ErrorAction SilentlyContinue
Write-Host "  [ OK ] Visual effects: 'Let Windows choose' | transparency on" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 6. NETWORK: back to defaults
# ---------------------------------------------------------
Write-Host "  [6/11] Restoring network defaults..." -ForegroundColor Cyan
netsh int tcp set global autotuninglevel=normal | Out-Null
netsh int tcp set global initialRto=1000 | Out-Null
$interfacesKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
Get-ChildItem $interfacesKey -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $_.PSPath -Name "TCPNoDelay" -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $_.PSPath -Name "TcpDelAckTicks" -Force -ErrorAction SilentlyContinue
}
$sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 20 -Type DWord -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "MaxCacheTtl" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "MaxNegativeCacheTtl" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS" -Name "Do not use NLA" -Force -ErrorAction SilentlyContinue
$adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
foreach ($adapter in $adapters) {
    try { Enable-NetAdapterRsc -Name $adapter.Name -ErrorAction SilentlyContinue } catch { }
}
Write-Host "  [ OK ] TCP, Nagle, throttling, DNS, QoS, RSC -> defaults" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 7. DELIVERY OPTIMIZATION: default download mode
# ---------------------------------------------------------
Write-Host "  [7/11] Restoring Delivery Optimization defaults..." -ForegroundColor Cyan
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Force -ErrorAction SilentlyContinue
Write-Host "  [ OK ] Download mode restored to Windows default" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 8. NVIDIA: remove optimizer values
# ---------------------------------------------------------
Write-Host "  [8/11] Removing NVIDIA registry overrides..." -ForegroundColor Cyan
$classGuid = "{4d36e968-e325-11ce-bfc1-08002be10318}"
$basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$classGuid"
if (Test-Path $basePath) {
    Get-ChildItem $basePath -ErrorAction SilentlyContinue | Where-Object {
        ($_.GetValue("DriverDesc") -like "*NVIDIA*")
    } | ForEach-Object {
        foreach ($v in @("PowerMizerEnable","PowerMizerLevel","PowerMizerLevelAC","PerLevelGPUCacheSize","ShaderCacheSize","MSISupported","MessageNumberLimit")) {
            Remove-ItemProperty -Path $_.PSPath -Name $v -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "  [ OK ] NVIDIA driver values + MSI mode removed" -ForegroundColor Green
}
Write-Host ""

# ---------------------------------------------------------
# 9. SSD / NTFS: restore defaults
# ---------------------------------------------------------
Write-Host "  [9/11] Restoring SSD / NTFS defaults..." -ForegroundColor Cyan
$ntfsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
if (Test-Path $ntfsKey) {
    Set-ItemProperty -Path $ntfsKey -Name "NtfsDisable8dot3NameCreation" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $ntfsKey -Name "NtfsDisableLastAccessUpdate" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $ntfsKey -Name "NtfsMemoryUsage" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $ntfsKey -Name "PathCache" -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $ntfsKey -Name "NameCache" -Force -ErrorAction SilentlyContinue
    Write-Host "  [ OK ] NTFS settings restored to defaults" -ForegroundColor Green
}
# Restore disk timeout
$diskKey = "HKLM:\SYSTEM\CurrentControlSet\Services\disk"
if (Test-Path $diskKey) {
    Remove-ItemProperty -Path $diskKey -Name "TimeOutValue" -Force -ErrorAction SilentlyContinue
}
# Restore AHCI LPM
$ahciKey = "HKLM:\SYSTEM\CurrentControlSet\Services\storahci\Parameters\Device"
if (Test-Path $ahciKey) {
    Remove-ItemProperty -Path $ahciKey -Name "NoLPM" -Force -ErrorAction SilentlyContinue
}
Write-Host "  [ OK ] Storage power saving restored" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 10. TIMER & BCD: restore defaults
# ---------------------------------------------------------
Write-Host "  [10/11] Restoring timer and BCD defaults..." -ForegroundColor Cyan
try { bcdedit /deletevalue disabledynamictick 2>&1 | Out-Null } catch {}
try { bcdedit /deletevalue useplatformclock 2>&1 | Out-Null } catch {}
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" -Name "GlobalTimerResolutionRequests" -Force -ErrorAction SilentlyContinue
Write-Host "  [ OK ] Dynamic tick, platform clock, and global timer requests restored to defaults" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 11. POWER PLAN: Balanced
# ---------------------------------------------------------
Write-Host "  [11/11] Restoring Balanced power plan..." -ForegroundColor Cyan
powercfg -setactive 381b4222-f694-41f0-9685-ff5b8b25df2e | Out-Null
Write-Host "  [ OK ] Power plan: Balanced" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
Write-Host "  === UNDO COMPLETE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Everything is back to Windows defaults." -ForegroundColor Green
Write-Host ""
Write-Host "  [NOTE] REBOOT REQUIRED for service and HAGS changes to apply." -ForegroundColor Yellow
Write-Host "  [NOTE] Shader caches were not restored - they rebuild automatically." -ForegroundColor Gray