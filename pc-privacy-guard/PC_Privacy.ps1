#requires -version 5.1
<#[
PC Privacy Guard v2.1.1
Balanced and strict privacy profiles with exact state snapshots. The default
profile reduces personalization and activity upload without disabling services
needed by Windows Update, Insider builds, games, browsers, or device features.
]#>
param([switch]$DebugLog,[AllowEmptyString()][string]$ExpectedUserSid)
$ErrorActionPreference='Stop'
$Version='2.1.1'
$StateRoot=Join-Path $env:ProgramData 'WindowsPCToolkit\PrivacyGuard'
$SnapshotRoot=Join-Path $StateRoot 'Snapshots'
$script:CurrentSnapshot=$null
$PrivacyDebug=($DebugLog -or $env:WINDOWS_PC_TOOLKIT_DEBUG -eq '1')
$PrivacyLog=Join-Path $env:LOCALAPPDATA 'WindowsPCToolkit\Logs\PrivacyGuard.log'
function Write-PrivacyDiagnostic {
    param([string]$Kind,[string]$Message)
    if (-not $PrivacyDebug -and $Kind -notin @('FAIL','WARN')) { return }
    try {
        if ($Message.Length -gt 4096) { $Message=$Message.Substring(0,4096) }
        [IO.Directory]::CreateDirectory((Split-Path $PrivacyLog -Parent))|Out-Null
        [pscustomobject]@{Time=(Get-Date).ToString('o');Version=$Version;Kind=$Kind;Message=$Message} | ConvertTo-Json -Compress | Add-Content -LiteralPath $PrivacyLog -Encoding UTF8
    } catch { Write-Warning "Privacy diagnostic log could not be written: $($_.Exception.Message)" }
}
Write-PrivacyDiagnostic 'DEBUG' "Startup: state=$StateRoot; snapshots=$SnapshotRoot"

function Write-Status {
    param([ValidateSet('OK','INFO','WARN','FAIL','STEP')][string]$Kind,[string]$Message)
    $color=switch($Kind){'OK'{'Green'}'INFO'{'Cyan'}'WARN'{'Yellow'}'FAIL'{'Red'}default{'White'}}
    $tag=switch($Kind){'OK'{'[OK]'}'INFO'{'[i]'}'WARN'{'[!!]'}'FAIL'{'[X]'}default{'[>>]'}}
    Write-Host ("  {0} {1}" -f $tag,$Message) -ForegroundColor $color
    Write-PrivacyDiagnostic $Kind $Message
}
function Test-Admin {
    $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Assert-Admin {if(-not(Test-Admin)){throw 'Run this tool as Administrator.'}}
function Initialize-State{foreach($p in @($StateRoot,$SnapshotRoot)){if(-not(Test-Path -LiteralPath $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null}}}
function Get-RegState{
    param([string]$Path,[string]$Name)
    $exists=$false;$kind=$null;$value=$null
    if(Test-Path -LiteralPath $Path -ErrorAction Stop){$key=Get-Item -LiteralPath $Path -ErrorAction Stop;if($key.GetValueNames()-contains $Name){$exists=$true;$kind=$key.GetValueKind($Name).ToString();$value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}}
    [pscustomobject]@{Path=$Path;Name=$Name;Exists=$exists;Kind=$kind;Value=$value}
}
function Set-RegExact{
    param([string]$Path,[string]$Name,[object]$Value,[string]$Kind='DWord')
    if(-not(Test-Path -LiteralPath $Path)){New-Item -Path $Path -Force|Out-Null}
    if ($Kind -notin @('String','ExpandString','Binary','DWord','MultiString','QWord')) { throw "Unsupported registry value type: $Kind" }
    $type=$Kind
    $typed=$Value
    switch($type){'Binary'{$typed=[byte[]]@($Value)}'DWord'{$typed=[int]$Value}'QWord'{$typed=[long]$Value}'MultiString'{$typed=[string[]]@($Value)}}
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $typed -PropertyType $type -Force|Out-Null
    $actual=Get-RegState $Path $Name
    if (-not $actual.Exists -or $actual.Kind -ne $type -or (ConvertTo-Json -InputObject $actual.Value -Compress) -cne (ConvertTo-Json -InputObject $typed -Compress)) { throw "Registry write read-back failed: $Path\$Name" }
}
function Restore-RegState{
    param([pscustomobject]$State)
    if($State.Exists){Set-RegExact $State.Path $State.Name $State.Value $State.Kind}
    elseif((Get-RegState $State.Path $State.Name).Exists){Remove-ItemProperty -LiteralPath $State.Path -Name $State.Name -ErrorAction Stop}
    $actual=Get-RegState $State.Path $State.Name
    if($actual.Exists -ne $State.Exists -or ($actual.Exists -and ($actual.Kind -ne $State.Kind -or (ConvertTo-Json -InputObject $actual.Value -Compress) -cne (ConvertTo-Json -InputObject $State.Value -Compress)))){throw "Registry restore read-back failed: $($State.Path)\$($State.Name)"}
}
function Get-PrivacyTargets{
    @(
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo';N='Enabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy';N='TailoredExperiencesWithDiagnosticDataEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy';N='LetAppsUseAdvertisingId'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='ContentDeliveryAllowed'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='OemPreInstalledAppsEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='PreInstalledAppsEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='PreInstalledAppsEverEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='SilentInstalledAppsEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='SystemPaneSuggestionsEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='SubscribedContent-338388Enabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='SubscribedContent-338389Enabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='SubscribedContent-353694Enabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='SubscribedContent-353696Enabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='SubscribedContent-353698Enabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='SubscribedContent-88000326Enabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='RotatingLockScreenEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='RotatingLockScreenOverlayEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';N='SoftLandingEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement';N='ScoobeSystemSettingEnabled'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';N='EnableActivityFeed'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';N='PublishUserActivities'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';N='UploadUserActivities'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection';N='AllowTelemetry'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection';N='DoNotShowFeedbackNotifications'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';N='DisableTailoredExperiencesWithDiagnosticData'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';N='DisableWindowsConsumerFeatures'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization';N='DODownloadMode'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors';N='DisableLocation'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors';N='DisableWindowsLocationProvider'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors';N='DisableLocationScripting'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location';N='Value'},
        @{P='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location';N='Value'},
        @{P='HKCU:\Software\Policies\Microsoft\Edge';N='MetricsReportingEnabled'},
        @{P='HKCU:\Software\Policies\Microsoft\Edge';N='PersonalizationReportingEnabled'},
        @{P='HKCU:\Software\Policies\Microsoft\Edge';N='UserFeedbackAllowed'},
        @{P='HKCU:\Software\Policies\Google\Chrome';N='MetricsReportingEnabled'},
        @{P='HKCU:\Software\Policies\Google\Chrome';N='UrlKeyedAnonymizedDataCollectionEnabled'},
        @{P='HKCU:\Software\Policies\Google\Chrome';N='UserFeedbackAllowed'},
        @{P='HKLM:\SOFTWARE\Policies\Mozilla\Firefox';N='DisableTelemetry'},
        @{P='HKLM:\SOFTWARE\Policies\Mozilla\Firefox';N='DisableDefaultBrowserAgent'},
        @{P='HKLM:\SOFTWARE\Policies\Mozilla\Firefox';N='DisableFirefoxStudies'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';N='AllowCloudSearch'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';N='EnableDynamicContentInWSB'},
        @{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';N='AllowSearchToUseLocation'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings';N='IsMSACloudSearchEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings';N='IsAADCloudSearchEnabled'},
        @{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings';N='IsDeviceSearchHistoryEnabled'}
    )
}
function Get-TaskTargets{
    @(
        @{Path='\Microsoft\Windows\Application Experience\';Name='Microsoft Compatibility Appraiser'},
        @{Path='\Microsoft\Windows\Application Experience\';Name='ProgramDataUpdater'},
        @{Path='\Microsoft\Windows\Customer Experience Improvement Program\';Name='Consolidator'},
        @{Path='\Microsoft\Windows\Customer Experience Improvement Program\';Name='UsbCeip'},
        @{Path='\Microsoft\Windows\DiskDiagnostic\';Name='Microsoft-Windows-DiskDiagnosticDataCollector'}
    )
}
function New-PrivacySnapshot{
    param([string]$Reason='Privacy change')
    Write-PrivacyDiagnostic 'DEBUG' "Snapshot requested: $Reason"
    Initialize-State
    $regs=foreach($t in Get-PrivacyTargets){Get-RegState $t.P $t.N}
    $services=@(Get-CimInstance Win32_Service -Filter "Name='DiagTrack' OR Name='dmwappushservice'" -ErrorAction Stop | ForEach-Object {
        if ($_.StartMode -notin @('Auto','Manual','Disabled') -or $_.State -notin @('Running','Stopped')) { throw "Service is not in a restorable state: $($_.Name) ($($_.StartMode), $($_.State)). Retry after it settles." }
        [pscustomobject]@{Name=$_.Name;StartMode=$_.StartMode;State=$_.State;DelayedAutoStart=(Get-RegState "HKLM:\SYSTEM\CurrentControlSet\Services\$($_.Name)" 'DelayedAutoStart')}
    })
    $availableTasks=@(Get-ScheduledTask -ErrorAction Stop)
    $tasks=foreach($t in Get-TaskTargets){$task=$availableTasks | Where-Object { $_.TaskPath -eq $t.Path -and $_.TaskName -eq $t.Name };if($task){[pscustomobject]@{Path=$t.Path;Name=$t.Name;Enabled=[bool]$task.Settings.Enabled}}}
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $obj=[pscustomobject]@{Schema=1;Version=$Version;Computer=$env:COMPUTERNAME;User=$identity.Name;UserSid=$identity.User.Value;Created=(Get-Date).ToString('o');Reason=$Reason;Registry=@($regs);Services=@($services);Tasks=@($tasks)}
    $path=Join-Path $SnapshotRoot ("privacy_{0}_{1}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'),[guid]::NewGuid().ToString('N'))
    $obj|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
    $verified=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ((ConvertTo-Json -InputObject $verified -Depth 8 -Compress) -ne (ConvertTo-Json -InputObject $obj -Depth 8 -Compress)) { throw 'Privacy backup verification failed; no privacy settings were changed.' }
    Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $path -Encoding UTF8
    $script:CurrentSnapshot=$path
    Write-Status OK ("Safety snapshot saved: {0}" -f $path)
    return $path
}
function Ensure-Snapshot{param([string]$Reason)if(-not $script:CurrentSnapshot){New-PrivacySnapshot $Reason|Out-Null}}
function Get-LatestSnapshot{
    $pointer=Join-Path $StateRoot 'latest_snapshot.txt';if(Test-Path -LiteralPath $pointer){$p=(Get-Content -LiteralPath $pointer -Raw).Trim();if(Test-Path -LiteralPath $p){return $p}}
    $f=Get-ChildItem -LiteralPath $SnapshotRoot -Filter 'privacy_*.json' -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1;if($f){return $f.FullName};return $null
}
function Restore-LatestSnapshot{
    Assert-Admin;Initialize-State;$path=Get-LatestSnapshot;if(-not $path){Write-Status WARN 'No Privacy Guard snapshot exists.';return}
    $snap=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    if ($snap.PSObject.Properties.Name -contains 'Schema' -and $snap.Schema -ne 1) { throw 'Unsupported privacy backup schema.' }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if ($snap.PSObject.Properties.Name -notcontains 'Computer' -or $snap.PSObject.Properties.Name -notcontains 'User') {
        Write-Status WARN 'This legacy privacy backup did not record its computer or user. Its origin cannot be verified.'
        if ((Read-Host '  Restore this legacy backup to the current computer and user? (y/N)') -notmatch '^[Yy]$') { throw 'Legacy privacy restore cancelled; no settings were changed.' }
    } elseif ($snap.Computer -ne $env:COMPUTERNAME -or ($snap.PSObject.Properties.Name -contains 'UserSid' -and $snap.UserSid -ne $identity.User.Value) -or ($snap.PSObject.Properties.Name -notcontains 'UserSid' -and $snap.User -ne $identity.Name)) { throw 'This privacy snapshot belongs to another computer or user.' }
    foreach($s in @($snap.Services)) {
        if ($s.StartMode -notin @('Auto','Manual','Disabled') -or $s.State -notin @('Running','Stopped')) { throw "Unsupported saved service state: $($s.Name). No settings were changed." }
    }
    foreach($s in @($snap.Registry)){Restore-RegState $s}
    foreach($s in @($snap.Services)){
        $type=switch($s.StartMode){'Auto'{'Automatic'}'Manual'{'Manual'}'Disabled'{'Disabled'}default{$null}}
        if(-not $type){throw "Unsupported saved service mode: $($s.Name)"}
        Set-Service -Name $s.Name -StartupType $type -ErrorAction Stop
        if ($s.PSObject.Properties.Name -contains 'DelayedAutoStart') { Restore-RegState $s.DelayedAutoStart }
        if($s.State -eq 'Running'){Start-Service -Name $s.Name -ErrorAction Stop}elseif($s.State -eq 'Stopped'){Stop-Service -Name $s.Name -Force -ErrorAction Stop}
        $actual=Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $s.Name) -ErrorAction Stop
        if($actual.StartMode -ne $s.StartMode -or $actual.State -ne $s.State){throw "Service restore read-back failed: $($s.Name)"}
    }
    foreach($t in @($snap.Tasks)){
        if($t.Enabled){Enable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop|Out-Null}else{Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop|Out-Null}
        if([bool](Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop).Settings.Enabled -ne [bool]$t.Enabled){throw "Task restore read-back failed: $($t.Name)"}
    }
    Write-Status OK ("Exact state restored from {0}" -f $path)
    Write-Status INFO 'No browser policy key was deleted wholesale. Unrelated policy values were preserved.'
    $script:CurrentSnapshot=$null
}
function Apply-PersonalizationPrivacy{
    Ensure-Snapshot 'Personalization privacy'
    Set-RegExact 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 DWord
    Set-RegExact 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 DWord
    Set-RegExact 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'LetAppsUseAdvertisingId' 2 DWord
    $cdm='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach($n in @('ContentDeliveryAllowed','OemPreInstalledAppsEnabled','PreInstalledAppsEnabled','PreInstalledAppsEverEnabled','SilentInstalledAppsEnabled','SystemPaneSuggestionsEnabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled','SubscribedContent-353698Enabled','SubscribedContent-88000326Enabled','SoftLandingEnabled')){Set-RegExact $cdm $n 0 DWord}
    Set-RegExact 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0 DWord
    Set-RegExact 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1 DWord
    Set-RegExact 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 DWord
    Write-Status OK 'Advertising ID, tailored experiences, suggestions, and consumer-content installs disabled.'
}
function Apply-ActivityPrivacy{
    Ensure-Snapshot 'Activity privacy'
    $p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    Set-RegExact $p 'EnableActivityFeed' 0 DWord;Set-RegExact $p 'PublishUserActivities' 0 DWord;Set-RegExact $p 'UploadUserActivities' 0 DWord
    Write-Status OK 'Activity feed publishing and cloud upload disabled.'
}
function Apply-DiagnosticPromptPrivacy{
    Ensure-Snapshot 'Diagnostic feedback prompt privacy'
    Set-RegExact 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1 DWord
    Write-Status OK 'Windows feedback-request notifications disabled. The current diagnostic-data level was preserved.'
}
function Apply-RequiredDiagnostics{
    Ensure-Snapshot 'Required diagnostics profile'
    Set-RegExact 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1 DWord
    Set-RegExact 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1 DWord
    Write-Status OK 'Diagnostic-data policy set to Required.'
    Write-Status WARN 'Windows Insider channels and some managed update/reporting features can require Optional diagnostic data. Use Undo if enrollment or update settings become unavailable.'
}
function Apply-BrowserTelemetryPolicies{
    Ensure-Snapshot 'Browser telemetry policies'
    foreach($x in @(
        @{P='HKCU:\Software\Policies\Microsoft\Edge';N='MetricsReportingEnabled'},@{P='HKCU:\Software\Policies\Microsoft\Edge';N='PersonalizationReportingEnabled'},@{P='HKCU:\Software\Policies\Microsoft\Edge';N='UserFeedbackAllowed'},
        @{P='HKCU:\Software\Policies\Google\Chrome';N='MetricsReportingEnabled'},@{P='HKCU:\Software\Policies\Google\Chrome';N='UrlKeyedAnonymizedDataCollectionEnabled'},@{P='HKCU:\Software\Policies\Google\Chrome';N='UserFeedbackAllowed'}
    )){Set-RegExact $x.P $x.N 0 DWord}
    foreach($n in @('DisableTelemetry','DisableDefaultBrowserAgent','DisableFirefoxStudies')){Set-RegExact 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' $n 1 DWord}
    Write-Status OK 'Browser metrics, studies, personalization reporting, and feedback prompts disabled.'
    Write-Status INFO 'Search suggestions, network prediction, sign-in, extensions, passwords, homepage, and proxy settings were not changed.'
}
function Apply-LocationPrivacy{
    Ensure-Snapshot 'Location privacy'
    $p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
    Set-RegExact $p 'DisableLocation' 1 DWord;Set-RegExact $p 'DisableWindowsLocationProvider' 1 DWord;Set-RegExact $p 'DisableLocationScripting' 1 DWord
    Set-RegExact 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' String
    Set-RegExact 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' String
    Write-Status OK 'Windows location provider and app location capability disabled.'
    Write-Status INFO 'This does not hide your public IP or prevent websites from estimating location from the network address. A VPN is the layer that changes public IP.'
}
function Apply-CloudSearchPrivacy{
    Ensure-Snapshot 'Cloud search privacy'
    $policy='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    Set-RegExact $policy 'AllowCloudSearch' 0 DWord
    Set-RegExact $policy 'EnableDynamicContentInWSB' 0 DWord
    Set-RegExact $policy 'AllowSearchToUseLocation' 0 DWord
    $user='HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
    Set-RegExact $user 'IsMSACloudSearchEnabled' 0 DWord
    Set-RegExact $user 'IsAADCloudSearchEnabled' 0 DWord
    Set-RegExact $user 'IsDeviceSearchHistoryEnabled' 0 DWord
    Write-Status OK 'Cloud-source search, search highlights, location-aware search, and device search history disabled where supported.'
    Write-Status INFO 'Windows Home can ignore some organization policies; the reversible per-user cloud-search toggles are also applied.'
}
function Apply-StrictTelemetryServiceProfile{
    Ensure-Snapshot 'Strict telemetry service profile'
    $snapshot=Get-Content -LiteralPath $script:CurrentSnapshot -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($saved in @($snapshot.Services)){
        $name=$saved.Name
        Stop-Service -Name $name -Force -ErrorAction Stop
        Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
        $actual=Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $name) -ErrorAction Stop
        if (-not $actual -or $actual.StartMode -ne 'Disabled' -or $actual.State -ne 'Stopped') { throw "Service disable read-back failed: $name" }
        Write-Status OK ("Disabled service: {0}" -f $name)
    }
    foreach($t in @($snapshot.Tasks)){
        Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop|Out-Null
        if ([bool](Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop).Settings.Enabled) { throw "Task disable read-back failed: $($t.Name)" }
        Write-Status OK ("Disabled task: {0}{1}" -f $t.Path,$t.Name)
    }
    Write-Status WARN 'Strict mode can reduce diagnostic data available to Microsoft support and compatibility analysis.'
    Write-Status INFO 'Windows Update, BITS, Delivery Optimization, DNS Client, Defender, Store, Xbox, audio, GPU, camera, microphone, and Windows Insider Service were not disabled.'
}
function Apply-DeliveryOptimizationPrivacy{
    Ensure-Snapshot 'Delivery Optimization privacy'
    Set-RegExact 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 DWord
    Write-Status OK 'Delivery Optimization set to HTTP-only. Windows Update and Store downloads remain enabled; peer-to-peer sharing is disabled.'
}
function Apply-BalancedProfile{
    Assert-Admin;New-PrivacySnapshot 'Balanced privacy profile'|Out-Null
    Apply-PersonalizationPrivacy;Apply-ActivityPrivacy;Apply-DiagnosticPromptPrivacy;Apply-BrowserTelemetryPolicies;Apply-DeliveryOptimizationPrivacy
    Write-Status OK 'Balanced privacy profile complete.'
    Write-Status INFO 'Location, search integration, services, scheduled tasks, browsing features, and per-app permissions were left unchanged.'
}
function Apply-StrictProfile{
    Assert-Admin
    Write-Status WARN 'Strict mode disables Windows location, cloud search, DiagTrack, dmwappushservice, and selected telemetry tasks.'
    $c=Read-Host '  Continue with strict mode? (y/N)';if($c -notmatch '^[Yy]$'){Write-Status INFO 'Cancelled.';return}
    New-PrivacySnapshot 'Strict privacy profile'|Out-Null
    Apply-PersonalizationPrivacy;Apply-ActivityPrivacy;Apply-RequiredDiagnostics;Apply-BrowserTelemetryPolicies;Apply-DeliveryOptimizationPrivacy;Apply-LocationPrivacy;Apply-CloudSearchPrivacy;Apply-StrictTelemetryServiceProfile
    Write-Status OK 'Strict privacy profile complete. Reboot recommended.'
}
function Open-DnsManager{
    $path=$null
    foreach($candidate in @(
        (Join-Path $PSScriptRoot 'Optional DNS\DNS_Manager.ps1'),
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'dns-encrypted-doh\DNS_Manager.ps1')
    )){
        $resolved=[IO.Path]::GetFullPath($candidate)
        if(Test-Path -LiteralPath $resolved -PathType Leaf){$path=$resolved;break}
    }
    if($path){& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $path}else{Write-Status WARN 'DNS Manager not found.'}
}
function Show-Dashboard{
    Write-Host '  CURRENT STATUS' -ForegroundColor Cyan
    $checks=@(
        @{L='Advertising ID off';P='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo';N='Enabled';V=0},
        @{L='Activity upload off';P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';N='UploadUserActivities';V=0},
        @{L='Required diagnostics policy';P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection';N='AllowTelemetry';V=1},
        @{L='Windows location policy off';P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors';N='DisableLocation';V=1}
    )
    foreach($x in $checks){$ok=$false;try{$ok=((Get-ItemProperty -LiteralPath $x.P -Name $x.N -ErrorAction Stop).($x.N)-eq $x.V)}catch{};$mark=if($ok){'[ON]'}else{'[--]'};$color=if($ok){'Green'}else{'DarkGray'};Write-Host ("  {0} {1}" -f $mark,$x.L) -ForegroundColor $color}
    foreach($name in @('DiagTrack','wisvc','wuauserv','DoSvc','BITS')){$s=Get-Service -Name $name -ErrorAction SilentlyContinue;if($s){Write-Host ("  Service {0,-12}: {1}" -f $name,$s.Status)}}
    Write-Host ''
}
function Show-Header{
    Clear-Host
    Write-Host '  ================================================================' -ForegroundColor DarkCyan
    Write-Host ("  PC PRIVACY GUARD  v{0}" -f $Version) -ForegroundColor Yellow
    Write-Host '  Exact rollback, balanced defaults, strict mode by explicit choice' -ForegroundColor Gray
    Write-Host '  ================================================================' -ForegroundColor DarkCyan
    Write-Host ''
}
function Show-Menu{
    Write-Host '  [A] Balanced Privacy Profile (recommended)' -ForegroundColor Green
    Write-Host '      Personalization, activity upload, browser metrics, P2P updates'
    Write-Host '  [S] Strict Privacy Profile'
    Write-Host '      Adds location, cloud search, telemetry services and tasks'
    Write-Host ''
    Write-Host '  [1] Personalization and advertising'
    Write-Host '  [2] Activity history upload'
    Write-Host '  [3] Required diagnostic-data policy (explicit; may affect Insider)'
    Write-Host '  [4] Browser telemetry policies'
    Write-Host '  [5] Windows location privacy'
    Write-Host '  [6] Cloud search privacy'
    Write-Host '  [7] Delivery Optimization privacy'
    Write-Host '  [8] Strict telemetry services/tasks'
    Write-Host '  [D] Encrypted DNS Manager'
    Write-Host '  [U] Restore exact latest snapshot' -ForegroundColor Yellow
    Write-Host '  [0] Exit'
    Write-Host ''
}

try {
    if ($ExpectedUserSid -and [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedUserSid) { throw 'Privacy Guard was elevated as a different Windows user. Run with administrator rights for your own account; no privacy settings were changed.' }
    Assert-Admin;Initialize-State
} catch { Write-PrivacyDiagnostic 'FAIL' $_.Exception.Message; throw }
while($true){
    $script:CurrentSnapshot=$null;Show-Header;Show-Dashboard;Show-Menu;$c=(Read-Host '  Select').Trim().ToUpperInvariant();Write-PrivacyDiagnostic 'DEBUG' "Selected action: $c"
    try{switch($c){'A'{Apply-BalancedProfile}'S'{Apply-StrictProfile}'1'{New-PrivacySnapshot 'Personalization privacy'|Out-Null;Apply-PersonalizationPrivacy}'2'{New-PrivacySnapshot 'Activity privacy'|Out-Null;Apply-ActivityPrivacy}'3'{New-PrivacySnapshot 'Required diagnostics policy'|Out-Null;Apply-RequiredDiagnostics}'4'{New-PrivacySnapshot 'Browser telemetry policies'|Out-Null;Apply-BrowserTelemetryPolicies}'5'{New-PrivacySnapshot 'Location privacy'|Out-Null;Apply-LocationPrivacy}'6'{New-PrivacySnapshot 'Cloud search privacy'|Out-Null;Apply-CloudSearchPrivacy}'7'{New-PrivacySnapshot 'Delivery Optimization privacy'|Out-Null;Apply-DeliveryOptimizationPrivacy}'8'{New-PrivacySnapshot 'Strict telemetry services'|Out-Null;Apply-StrictTelemetryServiceProfile}'D'{Open-DnsManager}'U'{Restore-LatestSnapshot}'0'{break}default{Write-Status WARN 'Invalid selection.'}}}catch{Write-Status FAIL $_.Exception.Message}
    if($c -eq '0'){break};Write-Host '';Read-Host '  Press Enter to continue'|Out-Null
}
