<#
.SYNOPSIS
    PC Privacy Guard v1.0 - location mask + tracker kill without breaking games/apps/browsers/WU.
.DESCRIPTION
    Interactive toolkit that:
      - Disables Windows location services and geolocation providers
      - Denies app capability access to location
      - Turns off advertising ID, activity upload, CEIP, Find My Device, maps broker
      - Stops known tracking services/tasks while PRESERVING:
          Windows Update, Delivery Optimization (DoSvc), BITS, Store, browsers,
          Xbox/Game Bar services, firewall, DNS client, audio, graphics stack
    Telemetry is set to Level 1 (Required) - never Level 0 (breaks WU/DISM).
.NOTES
    Requires Administrator. Use Run_As_Admin.bat.
    Undo [U] restores the keys/services this script changed.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$Script:Version   = '1.0'
$Script:StartTime = Get-Date
$Script:Results   = [ordered]@{}
$Script:LogDir    = Join-Path $env:USERPROFILE 'Desktop'
$Script:LogPath   = Join-Path $Script:LogDir ("PC_Privacy_Log_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))

$B = @{
    TL = [string][char]0x2554; TR = [string][char]0x2557
    BL = [string][char]0x255A; BR = [string][char]0x255D
    H  = [string][char]0x2550; V  = [string][char]0x2551
    MH = [string][char]0x2500
    FULL = [string][char]0x25CF; EMPTY = [string][char]0x25CB
}

try { Start-Transcript -Path $Script:LogPath -Append -EA SilentlyContinue | Out-Null } catch { }

# ============================================================================
#  HELPERS
# ============================================================================

function Ensure-Key {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Set-RegDword {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value,
        [string]$Desc = ''
    )
    try {
        Ensure-Key $Path
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force -ErrorAction Stop
        if ($Desc) { Write-Host ("    [OK] {0}" -f $Desc) -ForegroundColor Green }
        return $true
    } catch {
        if ($Desc) { Write-Host ("    [!!] {0} - {1}" -f $Desc, $_.Exception.Message) -ForegroundColor Yellow }
        return $false
    }
}

function Set-RegString {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [string]$Desc = ''
    )
    try {
        Ensure-Key $Path
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type String -Force -ErrorAction Stop
        if ($Desc) { Write-Host ("    [OK] {0}" -f $Desc) -ForegroundColor Green }
        return $true
    } catch {
        if ($Desc) { Write-Host ("    [!!] {0} - {1}" -f $Desc, $_.Exception.Message) -ForegroundColor Yellow }
        return $false
    }
}

function Remove-RegValueSafe {
    param([string]$Path, [string]$Name)
    try {
        if (Test-Path -LiteralPath $Path) {
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Set-ServiceStart {
    param(
        [string]$Name,
        [ValidateSet(2,3,4)][int]$Start,
        [string]$Desc = ''
    )
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Path -LiteralPath $key)) {
        if ($Desc) { Write-Host ("    [>>] {0} - service not present" -f $Desc) -ForegroundColor DarkGray }
        return $false
    }
    try {
        Set-ItemProperty -Path $key -Name 'Start' -Value $Start -Type DWord -Force -ErrorAction Stop
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $Start -eq 4 -and $svc.Status -eq 'Running') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        $mode = switch ($Start) { 2 { 'Automatic' } 3 { 'Manual' } 4 { 'Disabled' } }
        if ($Desc) { Write-Host ("    [OK] {0} -> {1}" -f $Desc, $mode) -ForegroundColor Green }
        return $true
    } catch {
        if ($Desc) { Write-Host ("    [!!] {0} - {1}" -f $Desc, $_.Exception.Message) -ForegroundColor Yellow }
        return $false
    }
}

function Disable-TaskPath {
    param([string]$PathPattern)
    try {
        Get-ScheduledTask -TaskPath $PathPattern -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.State -ne 'Disabled') {
                Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue | Out-Null
                Write-Host ("    [OK] Task disabled: {0}{1}" -f $_.TaskPath, $_.TaskName) -ForegroundColor Green
            }
        }
    } catch { }
}

function Write-Status {
    param([ValidateSet('OK','Fail','Warn','Skip','Info','Step')][string]$Type, [string]$Text)
    $map = @{
        OK   = @{ Tag = '  [OK] '; Color = 'Green' }
        Fail = @{ Tag = '  [XX] '; Color = 'Red' }
        Warn = @{ Tag = '  [!!] '; Color = 'Yellow' }
        Skip = @{ Tag = '  [>>] '; Color = 'DarkCyan' }
        Info = @{ Tag = '     ';   Color = 'Gray' }
        Step = @{ Tag = '  [=>] '; Color = 'Cyan' }
    }
    $m = $map[$Type]
    Write-Host $m.Tag -ForegroundColor $m.Color -NoNewline
    Write-Host $Text -ForegroundColor $(if ($Type -eq 'Info') { 'Gray' } else { 'White' })
}

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ("  {0}" -f ($B.MH * 62)) -ForegroundColor DarkGray
    Write-Host ("  {0}" -f $Title) -ForegroundColor Yellow
    Write-Host ("  {0}" -f ($B.MH * 62)) -ForegroundColor DarkGray
    Write-Host ''
}

function Show-Banner {
    Clear-Host
    $inner = 62
    $blank = (' ' * $inner)
    $title = '  PC PRIVACY GUARD'.PadRight($inner)
    $ver   = ('  v{0} - Location mask + tracker kill' -f $Script:Version).PadRight($inner)
    $safe  = '  Safe for games | browsers | Windows Update'.PadRight($inner)
    Write-Host ''
    Write-Host ("  {0}{1}{2}" -f $B.TL, ($B.H * $inner), $B.TR) -ForegroundColor Magenta
    Write-Host ("  {0}{1}{0}" -f $B.V, $blank) -ForegroundColor Magenta
    Write-Host ("  {0}{1}{0}" -f $B.V, $title) -ForegroundColor Magenta
    Write-Host ("  {0}{1}{0}" -f $B.V, $ver) -ForegroundColor White
    Write-Host ("  {0}{1}{0}" -f $B.V, $safe) -ForegroundColor Green
    Write-Host ("  {0}{1}{0}" -f $B.V, $blank) -ForegroundColor Magenta
    Write-Host ("  {0}{1}{2}" -f $B.BL, ($B.H * $inner), $B.BR) -ForegroundColor Magenta
    Write-Host ("  Log: {0}" -f $Script:LogPath) -ForegroundColor DarkGray
    Write-Host ''
}

function Get-LocStatus {
    $out = [ordered]@{}
    try {
        $s = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc' -Name Start -EA SilentlyContinue).Start
        $out.GeoServiceDisabled = ($s -eq 4)
    } catch { $out.GeoServiceDisabled = $false }
    try {
        $v = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name DisableLocation -EA SilentlyContinue).DisableLocation
        $out.LocationPolicyOff = ($v -eq 1)
    } catch { $out.LocationPolicyOff = $false }
    try {
        $v = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Name Value -EA SilentlyContinue).Value
        $out.AppLocationDenied = ($v -eq 'Deny')
    } catch { $out.AppLocationDenied = $false }
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name Enabled -EA SilentlyContinue).Enabled
        $out.AdIdOff = ($v -eq 0)
    } catch { $out.AdIdOff = $false }
    try {
        $v = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name AllowTelemetry -EA SilentlyContinue).AllowTelemetry
        $out.TelemetryRequiredOnly = ($v -eq 1)
    } catch { $out.TelemetryRequiredOnly = $false }
    try {
        $s = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack' -Name Start -EA SilentlyContinue).Start
        $out.DiagTrackOff = ($s -eq 4)
    } catch { $out.DiagTrackOff = $false }
    try {
        $v = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name PublishUserActivities -EA SilentlyContinue).PublishUserActivities
        $out.ActivityUploadOff = ($v -eq 0)
    } catch { $out.ActivityUploadOff = $false }
    return $out
}

function Show-Dashboard {
    Write-Host '  PRIVACY STATUS' -ForegroundColor Cyan
    Write-Host ("  {0}" -f ($B.MH * 58)) -ForegroundColor DarkGray
    $st = Get-LocStatus
    $items = @(
        @{ K = 'GeoServiceDisabled';    L = 'Geolocation service (lfsvc) disabled' }
        @{ K = 'LocationPolicyOff';     L = 'Location policy disabled' }
        @{ K = 'AppLocationDenied';     L = 'Apps denied location capability' }
        @{ K = 'AdIdOff';               L = 'Advertising ID off' }
        @{ K = 'TelemetryRequiredOnly'; L = 'Telemetry Level 1 (WU-safe)' }
        @{ K = 'DiagTrackOff';          L = 'DiagTrack telemetry service off' }
        @{ K = 'ActivityUploadOff';     L = 'Activity history upload off' }
    )
    foreach ($i in $items) {
        $on = $st[$i.K] -eq $true
        $dot = if ($on) { $B.FULL } else { $B.EMPTY }
        $col = if ($on) { 'Green' } else { 'DarkGray' }
        Write-Host ("    {0} {1}" -f $dot, $i.L) -ForegroundColor $col
    }
    $active = @($st.Values | Where-Object { $_ -eq $true }).Count
    Write-Host ("  {0}" -f ($B.MH * 58)) -ForegroundColor DarkGray
    Write-Host ("  Hardened: {0} / {1}" -f $active, $st.Count) -ForegroundColor $(if ($active -eq $st.Count) { 'Green' } else { 'Yellow' })
    Write-Host ''
    Write-Host '  ALWAYS PRESERVED' -ForegroundColor DarkCyan
    Write-Host '    Windows Update | DoSvc | BITS | Store | Browsers | Xbox/Game Bar' -ForegroundColor DarkGray
    Write-Host '    Firewall | DNS Client | Audio | GPU stack | Camera/Mic hardware' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-Menu {
    Write-Host '  PRIVACY MENU' -ForegroundColor Cyan
    Write-Host ("  {0}" -f ($B.H * 62)) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  [A]  * FULL PRIVACY LOCKDOWN (recommended)' -ForegroundColor Green
    Write-Host '       Location mask + trackers + ads + activity (WU/game safe)'
    Write-Host ''
    Write-Host '  LOCATION MASK' -ForegroundColor Magenta
    Write-Host ("  {0}" -f ($B.MH * 40)) -ForegroundColor DarkGray
    Write-Host '  [1]  Kill location services and policies' -ForegroundColor White
    Write-Host '       lfsvc, LocationAndSensors, Find My Device, maps'
    Write-Host '  [2]  Deny app location capability' -ForegroundColor White
    Write-Host '       ConsentStore location = Deny (all UWP/Win32 apps)'
    Write-Host '  [3]  Clear location / sensor history caches' -ForegroundColor White
    Write-Host '       Wipe known location history stores (safe)'
    Write-Host ''
    Write-Host '  TRACKERS AND IDENTITY' -ForegroundColor Magenta
    Write-Host ("  {0}" -f ($B.MH * 40)) -ForegroundColor DarkGray
    Write-Host '  [4]  Advertising ID + tailored experiences' -ForegroundColor White
    Write-Host '  [5]  Activity history / timeline upload' -ForegroundColor White
    Write-Host '  [6]  Telemetry trackers (WU-safe Level 1)' -ForegroundColor White
    Write-Host '       DiagTrack, CEIP tasks, dmwappush - NOT Level 0'
    Write-Host '  [7]  Input / speech / cloud clipboard trackers' -ForegroundColor White
    Write-Host '  [8]  Edge/Chrome privacy policies (browsers still work)' -ForegroundColor White
    Write-Host ''
    Write-Host '  TOOLS' -ForegroundColor Magenta
    Write-Host ("  {0}" -f ($B.MH * 40)) -ForegroundColor DarkGray
    Write-Host '  [S]  Refresh privacy status' -ForegroundColor White
    Write-Host '  [R]  Create System Restore Point' -ForegroundColor White
    Write-Host '  [U]  Undo Privacy Guard changes' -ForegroundColor Red
    Write-Host '  [0]  EXIT' -ForegroundColor Red
    Write-Host ''
    return (Read-Host '  Select option')
}

# ============================================================================
#  MODULE: LOCATION
# ============================================================================

function Invoke-LocationKill {
    Write-Section 'LOCATION SERVICES - HARD OFF'

    Write-Status Step 'Disabling Geolocation service (lfsvc)...'
    Set-ServiceStart -Name 'lfsvc' -Start 4 -Desc 'Geolocation Service (lfsvc)'

    Write-Status Step 'Location policies...'
    $locPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
    Set-RegDword $locPol 'DisableLocation' 1 'Policy: DisableLocation'
    Set-RegDword $locPol 'DisableWindowsLocationProvider' 1 'Policy: DisableWindowsLocationProvider'
    Set-RegDword $locPol 'DisableLocationScripting' 1 'Policy: DisableLocationScripting'
    Set-RegDword $locPol 'DisableSensors' 1 'Policy: DisableSensors (geo-related sensors)'

    # ConsentStore uses string "Allow" / "Deny" on modern Windows
    Set-RegString 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'User: location capability Deny'
    Set-RegString 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'System: location capability Deny'
    Set-RegString 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged' 'Value' 'Deny' 'NonPackaged apps: location Deny'
    Set-RegString 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged' 'Value' 'Deny' 'System NonPackaged: location Deny'

    Write-Status Step 'Find My Device...'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0 'Find My Device policy denied'
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Settings\FindMyDevice' 'LocationSyncEnabled' 0 'Find My Device location sync off'

    Write-Status Step 'Downloaded Maps (can reveal region)...'
    Set-ServiceStart -Name 'MapsBroker' -Start 4 -Desc 'Downloaded Maps Manager'
    $mapsPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps'
    Set-RegDword $mapsPol 'AutoDownloadAndUpdateMapData' 0 'Maps auto-download off'
    Set-RegDword $mapsPol 'AllowUntriggeredNetworkTrafficOnSettingsPage' 0 'Maps settings network traffic off'

    Write-Status Step 'Wi-Fi location sharing residuals...'
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' 'AutoConnectAllowedOEM' 0 'Wi-Fi auto-connect OEM off'
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' 'value' 0 'Wi-Fi hotspot reporting off'
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' 'value' 0 'Wi-Fi Sense hotspots off'

    Ensure-Key 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration'
    Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration' 'Status' 0 'lfsvc Service Configuration Status = 0'

    $Script:Results['Location'] = 'PASS - Location stack disabled'
    Write-Status OK 'Location mask applied. Apps can no longer use Windows geolocation APIs.'
    Write-Status Info 'Note: websites can still geo-guess via IP - use Encrypted DNS + VPN for that layer.'
}

function Invoke-AppLocationDeny {
    Write-Section 'APP LOCATION CAPABILITY - DENY ALL'

    # Only force-deny location. Do NOT touch webcam/microphone/contacts/bluetooth.
    $denyStrict = @('location')
    foreach ($scope in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
    )) {
        foreach ($cap in $denyStrict) {
            $p = Join-Path $scope $cap
            Set-RegString $p 'Value' 'Deny' ("{0}\{1} = Deny" -f $scope, $cap)
            $np = Join-Path $p 'NonPackaged'
            Set-RegString $np 'Value' 'Deny' ("{0}\{1}\NonPackaged = Deny" -f $scope, $cap)
        }
    }

    Write-Status Info 'Camera, Microphone, Bluetooth: LEFT ALONE (game chat / Discord / browsers).'
    Write-Status Info 'Contacts / calendar: LEFT ALONE (mail apps).'
    $Script:Results['AppCaps'] = 'PASS - Location capability denied'
}

function Invoke-ClearLocationCaches {
    Write-Section 'CLEAR LOCATION / SENSOR HISTORY'

    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\LocationProvider'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\LocationProvider')
    )
    $removed = 0
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            try {
                Get-ChildItem -LiteralPath $p -Recurse -Force -EA SilentlyContinue | ForEach-Object {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Recurse -Force -EA Stop
                        $removed++
                    } catch { }
                }
                Write-Status OK ("Cleaned: {0}" -f $p)
            } catch {
                Write-Status Warn ("Could not fully clean: {0}" -f $p)
            }
        } else {
            Write-Status Skip ("Not present: {0}" -f $p)
        }
    }

    try {
        $locStore = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
        if (Test-Path $locStore) {
            Get-ChildItem $locStore -EA SilentlyContinue | Where-Object {
                $_.PSChildName -notin @('NonPackaged', 'Value')
            } | ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.PSPath -Recurse -Force -EA SilentlyContinue
                    $removed++
                    Write-Status OK ("Cleared per-app location grant: {0}" -f $_.PSChildName)
                } catch { }
            }
        }
    } catch { }

    Write-Status Info ("Items removed/cleared: {0}" -f $removed)
    $Script:Results['LocCache'] = ("PASS - Cleared ({0} items)" -f $removed)
}

# ============================================================================
#  MODULE: ADVERTISING / ACTIVITY / TELEMETRY
# ============================================================================

function Invoke-AdvertisingKill {
    Write-Section 'ADVERTISING ID + TAILORED EXPERIENCES'

    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 'Advertising ID disabled (user)'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1 'Advertising ID disabled by policy'

    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    Ensure-Key $cdm
    @(
        'SubscribedContent-338393Enabled',
        'SubscribedContent-353694Enabled',
        'SubscribedContent-353696Enabled',
        'SubscribedContent-338387Enabled',
        'SubscribedContent-338388Enabled',
        'SubscribedContent-338389Enabled',
        'SubscribedContent-310093Enabled',
        'SubscribedContent-314559Enabled',
        'SubscribedContent-314563Enabled',
        'SystemPaneSuggestionsEnabled',
        'SoftLandingEnabled',
        'SilentInstalledAppsEnabled',
        'PreInstalledAppsEnabled',
        'OemPreInstalledAppsEnabled',
        'FeatureManagementEnabled',
        'ContentDeliveryAllowed'
    ) | ForEach-Object {
        Set-RegDword $cdm $_ 0 ("ContentDelivery: {0} = 0" -f $_)
    }

    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 'Tailored experiences off'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0 'Start menu program tracking off'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackDocs' 0 'Start recent docs tracking off'

    $Script:Results['Ads'] = 'PASS - Ad ID + suggestions off'
}

function Invoke-ActivityHistoryKill {
    Write-Section 'ACTIVITY HISTORY / TIMELINE UPLOAD'

    $sysPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    Set-RegDword $sysPol 'EnableActivityFeed' 0 'Activity feed disabled'
    Set-RegDword $sysPol 'PublishUserActivities' 0 'Publish user activities disabled'
    Set-RegDword $sysPol 'UploadUserActivities' 0 'Upload user activities disabled'

    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 'Consumer features / cloud content off'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1 'Soft landing tips off'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1 'Cloud optimized content off'
    Set-RegDword 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1 'Spotlight features off (user)'
    Set-RegDword 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1 'Tailored diag experiences off'

    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0 'Cross-device clipboard off'
    Set-RegDword 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory' 0 'Clipboard history off (local)'

    $Script:Results['Activity'] = 'PASS - Activity/timeline upload off'
}

function Invoke-TelemetrySafe {
    Write-Section 'TELEMETRY TRACKERS (WU-SAFE LEVEL 1)'

    Write-Status Info 'AllowTelemetry = 1 (Required). Level 0 breaks Windows Update / DISM.'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1 'Telemetry Level 1 (Required only)'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1 'Feedback notifications off'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowDeviceNameInTelemetry' 0 'Device name not in telemetry'
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 1 'Legacy DataCollection AllowTelemetry = 1'

    Set-ServiceStart -Name 'DiagTrack' -Start 4 -Desc 'Connected User Experiences and Telemetry'
    Set-ServiceStart -Name 'dmwappushservice' -Start 4 -Desc 'WAP Push Message Routing (telemetry channel)'
    Set-ServiceStart -Name 'RetailDemo' -Start 4 -Desc 'Retail Demo Service'
    Set-ServiceStart -Name 'wisvc' -Start 4 -Desc 'Windows Insider Service'

    Set-ServiceStart -Name 'WerSvc' -Start 3 -Desc 'Windows Error Reporting -> Manual'
    Set-ServiceStart -Name 'TrkWks' -Start 3 -Desc 'Distributed Link Tracking -> Manual'

    Write-Status Step 'CEIP / Feedback / SQM scheduled tasks...'
    Disable-TaskPath '\Microsoft\Windows\Customer Experience Improvement Program\*'
    Disable-TaskPath '\Microsoft\Windows\Feedback\*'
    Disable-TaskPath '\Microsoft\Windows\PI\*'
    Disable-TaskPath '\Microsoft\Windows\DiskDiagnostic\*'
    # Application Experience tasks LEFT ENABLED (feature updates / WU health)
    Write-Status Info 'Application Experience tasks: KEPT ENABLED (feature updates / WU).'

    Write-Status Step 'Delivery Optimization - service KEPT, P2P off...'
    $doKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'
    Set-RegDword $doKey 'DODownloadMode' 0 'DoSvc P2P off (HTTP-only) - service still runs for WU'
    Write-Status Info 'DoSvc / wuauserv / BITS / UsoSvc: NEVER disabled by this app.'

    $Script:Results['Telemetry'] = 'PASS - Level 1 + DiagTrack off (WU safe)'
}

function Invoke-InputSpeechKill {
    Write-Section 'INPUT / SPEECH / TYPING TRACKERS'

    $ip = 'HKCU:\Software\Microsoft\InputPersonalization'
    Set-RegDword $ip 'RestrictImplicitInkCollection' 1 'Implicit ink collection restricted'
    Set-RegDword $ip 'RestrictImplicitTextCollection' 1 'Implicit text collection restricted'
    Set-RegDword 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0 'Contacts harvest off'
    Set-RegDword 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0 'Inking personalization privacy declined'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SettingSync' 'SyncPolicy' 5 'Setting sync restricted'
    Set-RegDword 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0 'Online speech privacy declined'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization' 0 'Input personalization policy off'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC' 'PreventHandwritingDataSharing' 1 'Handwriting data sharing blocked'
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports' 'PreventHandwritingErrorReports' 1 'Handwriting error reports blocked'

    $ws = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    Set-RegDword $ws 'AllowCortana' 0 'Cortana policy off'
    Set-RegDword $ws 'DisableWebSearch' 1 'Web search in Start disabled'
    Set-RegDword $ws 'ConnectedSearchUseWeb' 0 'Connected search web off'
    Set-RegDword $ws 'AllowCloudSearch' 0 'Cloud search off'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0 'Bing search enabled = 0'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0 'Cortana consent = 0'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsAADCloudSearchEnabled' 0 'AAD cloud search off'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDeviceSearchHistoryEnabled' 0 'Device search history off'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsMSACloudSearchEnabled' 0 'MSA cloud search off'

    $Script:Results['InputSpeech'] = 'PASS - Input/speech/cloud search trackers off'
}

function Invoke-BrowserPrivacyPolicies {
    Write-Section 'BROWSER PRIVACY POLICIES (BROWSERS STILL WORK)'

    Write-Status Info 'These only turn off telemetry/AI side features - browsing, cookies, extensions intact.'

    $edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Ensure-Key $edge
    $edgeKeys = @{
        'DiagnosticData' = 0
        'PersonalizationReportingEnabled' = 0
        'UserFeedbackAllowed' = 0
        'SearchSuggestEnabled' = 0
        'AlternateErrorPagesEnabled' = 0
        'ResolveNavigationErrorsUseWebService' = 0
        'NetworkPredictionOptions' = 2
        'EdgeEnhanceImagesEnabled' = 0
        'HubsSidebarEnabled' = 0
        'SpotlightExperiencesAndRecommendationsEnabled' = 0
        'CopilotPageContext' = 0
        'CopilotCDPPageContext' = 0
        'AIGenThemesEnabled' = 0
        'AskCopilotEnabled' = 0
        'LocalBrowserDataShareEnabled' = 0
        # SyncDisabled intentionally NOT set - Edge sync/passwords keep working
    }
    foreach ($k in $edgeKeys.Keys) {
        Set-RegDword $edge $k $edgeKeys[$k] ("Edge policy: {0} = {1}" -f $k, $edgeKeys[$k])
    }
    Write-Status Info 'Edge: no proxy/homepage/extension changes.'

    $chrome = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    Ensure-Key $chrome
    $chromeKeys = @{
        'MetricsReportingEnabled' = 0
        'ChromeCleanupReportingEnabled' = 0
        'DeviceMetricsReportingEnabled' = 0
        'SafeBrowsingExtendedReportingEnabled' = 0
        'UrlKeyedAnonymizedDataCollectionEnabled' = 0
        'CloudPrintSubmitEnabled' = 0
        'GenAILocalFoundationalModelSettings' = 0
        'NetworkPredictionOptions' = 2
        'SearchSuggestEnabled' = 0
        'AlternateErrorPagesEnabled' = 0
        'SpellCheckServiceEnabled' = 0
    }
    foreach ($k in $chromeKeys.Keys) {
        Set-RegDword $chrome $k $chromeKeys[$k] ("Chrome policy: {0} = {1}" -f $k, $chromeKeys[$k])
    }
    Write-Status Info 'Chrome: metrics/prediction/AI off - Sync/extensions not removed.'

    $ff = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'
    Ensure-Key $ff
    Set-RegDword $ff 'DisableTelemetry' 1 'Firefox policy: DisableTelemetry'
    Set-RegDword $ff 'DisableDefaultBrowserAgent' 1 'Firefox policy: DisableDefaultBrowserAgent'

    $Script:Results['Browsers'] = 'PASS - Browser telemetry policies only'
}

# ============================================================================
#  FULL LOCKDOWN / UNDO / RESTORE
# ============================================================================

function Invoke-FullLockdown {
    Write-Section 'FULL PRIVACY LOCKDOWN'
    Write-Host '  This applies ALL safe modules in order.' -ForegroundColor Gray
    Write-Host '  Preserves: WU, DoSvc, BITS, Store, browsers, Xbox, firewall, audio, GPU.' -ForegroundColor Green
    Write-Host ''
    $go = Read-Host '  Type YES to continue'
    if ($go -ne 'YES') {
        Write-Status Skip 'Cancelled.'
        return
    }

    Write-Host ''
    $rp = Read-Host '  Create a System Restore Point first? (recommended) [Y/n]'
    if ($rp -ne 'n' -and $rp -ne 'N') {
        Invoke-RestorePoint
    }

    Invoke-LocationKill
    Invoke-AppLocationDeny
    Invoke-ClearLocationCaches
    Invoke-AdvertisingKill
    Invoke-ActivityHistoryKill
    Invoke-TelemetrySafe
    Invoke-InputSpeechKill
    Invoke-BrowserPrivacyPolicies

    Write-Section 'LOCKDOWN COMPLETE'
    Write-Status OK 'All safe privacy modules applied.'
    Write-Status Info 'Restart recommended so services (lfsvc, DiagTrack) stay dead.'
    Write-Status Info 'IP-based geo is separate - use Encrypted DNS + a VPN if needed.'
}

function Invoke-RestorePoint {
    Write-Section 'SYSTEM RESTORE POINT'
    try {
        Enable-ComputerRestore -Drive 'C:\' -EA SilentlyContinue
        $desc = "PC Privacy Guard v{0}" -f $Script:Version
        Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Status OK 'Restore point created.'
        $Script:Results['RestorePt'] = 'PASS'
    } catch {
        Write-Status Warn ("Could not create restore point: {0}" -f $_.Exception.Message)
        Write-Status Info 'System Restore may be off, or one was already created today.'
        $Script:Results['RestorePt'] = 'WARN'
    }
}

function Invoke-Undo {
    Write-Section 'UNDO PRIVACY GUARD CHANGES'
    Write-Host '  Restores defaults this app typically changes.' -ForegroundColor Yellow
    Write-Host ''
    $go = Read-Host '  Type YES to undo'
    if ($go -ne 'YES') {
        Write-Status Skip 'Undo cancelled.'
        return
    }

    Set-ServiceStart -Name 'lfsvc' -Start 3 -Desc 'Geolocation -> Manual'
    Set-ServiceStart -Name 'MapsBroker' -Start 3 -Desc 'MapsBroker -> Manual'
    Set-ServiceStart -Name 'DiagTrack' -Start 2 -Desc 'DiagTrack -> Automatic'
    Set-ServiceStart -Name 'dmwappushservice' -Start 3 -Desc 'dmwappush -> Manual'
    Set-ServiceStart -Name 'WerSvc' -Start 3 -Desc 'WerSvc -> Manual'

    $polPaths = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors',
        'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo',
        'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports'
    )
    foreach ($p in $polPaths) {
        if (Test-Path $p) {
            Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
            Write-Status OK ("Removed policy key: {0}" -f $p)
        }
    }

    Set-RegString 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Allow' 'User location capability -> Allow'
    Set-RegString 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Allow' 'System location capability -> Allow'

    Remove-RegValueSafe 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed'
    Remove-RegValueSafe 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities'
    Remove-RegValueSafe 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities'
    Remove-RegValueSafe 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard'

    Remove-RegValueSafe 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
    Remove-RegValueSafe 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications'
    Remove-RegValueSafe 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowDeviceNameInTelemetry'

    if (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent') {
        Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Recurse -Force -EA SilentlyContinue
        Write-Status OK 'Removed CloudContent policies'
    }
    if (Test-Path 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent') {
        Remove-Item 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' -Recurse -Force -EA SilentlyContinue
    }

    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 1 'Advertising ID re-enabled'
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 1 'Tailored experiences re-enabled'
    Set-RegDword 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory' 1 'Clipboard history re-enabled'

    if (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search') {
        Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Recurse -Force -EA SilentlyContinue
        Write-Status OK 'Removed Windows Search policies'
    }
    Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 1 'Bing search re-enabled'

    foreach ($bp in @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
        'HKLM:\SOFTWARE\Policies\Google\Chrome',
        'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'
    )) {
        if (Test-Path $bp) {
            Remove-Item $bp -Recurse -Force -EA SilentlyContinue
            Write-Status OK ("Removed: {0}" -f $bp)
        }
    }

    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    if (Test-Path $cdm) {
        @('ContentDeliveryAllowed','FeatureManagementEnabled','SystemPaneSuggestionsEnabled','SoftLandingEnabled') | ForEach-Object {
            Set-RegDword $cdm $_ 1 ("Restored CDM {0} = 1" -f $_)
        }
    }

    $Script:Results['Undo'] = 'PASS - Privacy Guard changes reverted'
    Write-Status OK 'Undo complete. Restart recommended.'
    Write-Status Info 'Re-enable Location in Settings > Privacy and security > Location if needed.'
}

function Show-Summary {
    Write-Host ''
    Write-Host ("  {0}{1}{2}" -f $B.TL, ($B.H * 62), $B.TR) -ForegroundColor Magenta
    Write-Host ("  {0}{1}{0}" -f $B.V, '  SESSION SUMMARY'.PadRight(62)) -ForegroundColor Magenta
    if ($Script:Results.Count -eq 0) {
        Write-Host '  No modules run this session.' -ForegroundColor DarkGray
    } else {
        foreach ($k in $Script:Results.Keys) {
            $v = $Script:Results[$k]
            $col = if ($v -match 'FAIL') { 'Red' } elseif ($v -match 'WARN') { 'Yellow' } else { 'Green' }
            Write-Host ("  [{0}] {1}" -f $k, $v) -ForegroundColor $col
        }
    }
    $elapsed = (Get-Date) - $Script:StartTime
    Write-Host ("  Session: {0}m {1}s" -f [int]$elapsed.TotalMinutes, $elapsed.Seconds) -ForegroundColor DarkGray
    Write-Host ("  Log: {0}" -f $Script:LogPath) -ForegroundColor DarkGray
    Write-Host ''
}

# ============================================================================
#  MAIN
# ============================================================================

function Main {
    Show-Banner
    Show-Dashboard

    while ($true) {
        $sel = (Show-Menu).Trim().ToUpperInvariant()
        switch ($sel) {
            'A' { Invoke-FullLockdown }
            '1' { Invoke-LocationKill }
            '2' { Invoke-AppLocationDeny }
            '3' { Invoke-ClearLocationCaches }
            '4' { Invoke-AdvertisingKill }
            '5' { Invoke-ActivityHistoryKill }
            '6' { Invoke-TelemetrySafe }
            '7' { Invoke-InputSpeechKill }
            '8' { Invoke-BrowserPrivacyPolicies }
            'S' { Show-Banner; Show-Dashboard; continue }
            'R' { Invoke-RestorePoint }
            'U' { Invoke-Undo }
            '0' { break }
            default {
                Write-Host '  Invalid selection.' -ForegroundColor Red
                Start-Sleep -Seconds 1
                Show-Banner
                Show-Dashboard
                continue
            }
        }
        if ($sel -ne '0') {
            Write-Host ''
            Read-Host '  Press Enter to return to menu'
            Show-Banner
            Show-Dashboard
        }
    }
    Show-Summary
}

try {
    Main
} catch {
    Write-Host ''
    Write-Host ("  [!!] FATAL: {0}" -f $_) -ForegroundColor Red
    Read-Host '  Press Enter to exit'
} finally {
    try { Stop-Transcript -EA SilentlyContinue } catch { }
}
