#requires -version 5.1
<#[
PC Privacy Guard v2.0
Balanced and strict privacy profiles with exact state snapshots. The default
profile reduces personalization and activity upload without disabling services
needed by Windows Update, Insider builds, games, browsers, or device features.
]#>
$ErrorActionPreference='Stop'
$Version='2.0'
$StateRoot=Join-Path $env:ProgramData 'WindowsPCToolkit\PrivacyGuard'
$SnapshotRoot=Join-Path $StateRoot 'Snapshots'
$script:CurrentSnapshot=$null

function Write-Status {
    param([ValidateSet('OK','INFO','WARN','FAIL','STEP')][string]$Kind,[string]$Message)
    $color=switch($Kind){'OK'{'Green'}'INFO'{'Cyan'}'WARN'{'Yellow'}'FAIL'{'Red'}default{'White'}}
    $tag=switch($Kind){'OK'{'[OK]'}'INFO'{'[i]'}'WARN'{'[!!]'}'FAIL'{'[X]'}default{'[>>]'}}
    Write-Host ("  {0} {1}" -f $tag,$Message) -ForegroundColor $color
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
    if(Test-Path -LiteralPath $Path){try{$key=Get-Item -LiteralPath $Path -ErrorAction Stop;if($key.GetValueNames()-contains $Name){$exists=$true;$kind=$key.GetValueKind($Name).ToString();$value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}}catch{}}
    [pscustomobject]@{Path=$Path;Name=$Name;Exists=$exists;Kind=$kind;Value=$value}
}
function Set-RegExact{
    param([string]$Path,[string]$Name,[object]$Value,[string]$Kind='DWord')
    if(-not(Test-Path -LiteralPath $Path)){New-Item -Path $Path -Force|Out-Null}
    $type=switch($Kind){'String'{'String'}'ExpandString'{'ExpandString'}'Binary'{'Binary'}'DWord'{'DWord'}'MultiString'{'MultiString'}'QWord'{'QWord'}default{'String'}}
    $typed=switch($type){'Binary'{[byte[]]@($Value)}'DWord'{[int]$Value}'QWord'{[long]$Value}'MultiString'{[string[]]@($Value)}default{$Value}}
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $typed -PropertyType $type -Force|Out-Null
}
function Restore-RegState{
    param([pscustomobject]$State)
    if($State.Exists){Set-RegExact $State.Path $State.Name $State.Value $State.Kind}
    elseif(Test-Path -LiteralPath $State.Path){Remove-ItemProperty -LiteralPath $State.Path -Name $State.Name -ErrorAction SilentlyContinue}
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
    Initialize-State
    $regs=foreach($t in Get-PrivacyTargets){Get-RegState $t.P $t.N}
    $services=foreach($name in @('DiagTrack','dmwappushservice')){$s=Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $name) -ErrorAction SilentlyContinue;if($s){[pscustomobject]@{Name=$name;StartMode=$s.StartMode;State=$s.State}}}
    $tasks=foreach($t in Get-TaskTargets){$task=Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue;if($task){[pscustomobject]@{Path=$t.Path;Name=$t.Name;Enabled=($task.State -ne 'Disabled')}}}
    $obj=[pscustomobject]@{Schema=1;Version=$Version;Created=(Get-Date).ToString('o');Reason=$Reason;Registry=@($regs);Services=@($services);Tasks=@($tasks)}
    $path=Join-Path $SnapshotRoot ("privacy_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    $obj|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $path -Encoding ASCII
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
    $snap=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    foreach($s in @($snap.Registry)){Restore-RegState $s}
    foreach($s in @($snap.Services)){
        $type=switch($s.StartMode){'Auto'{'Automatic'}'Manual'{'Manual'}'Disabled'{'Disabled'}default{$null}}
        if($type){Set-Service -Name $s.Name -StartupType $type -ErrorAction SilentlyContinue}
        if($s.State -eq 'Running'){Start-Service -Name $s.Name -ErrorAction SilentlyContinue}elseif($s.State -eq 'Stopped'){Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue}
    }
    foreach($t in @($snap.Tasks)){if($t.Enabled){Enable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue|Out-Null}else{Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue|Out-Null}}
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
    foreach($name in @('DiagTrack','dmwappushservice')){if(Get-Service -Name $name -ErrorAction SilentlyContinue){Stop-Service -Name $name -Force -ErrorAction SilentlyContinue;Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue;Write-Status OK ("Disabled service: {0}" -f $name)}}
    foreach($t in Get-TaskTargets){if(Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue){Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue|Out-Null;Write-Status OK ("Disabled task: {0}{1}" -f $t.Path,$t.Name)}}
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

Assert-Admin;Initialize-State
while($true){
    $script:CurrentSnapshot=$null;Show-Header;Show-Dashboard;Show-Menu;$c=(Read-Host '  Select').Trim().ToUpperInvariant()
    try{switch($c){'A'{Apply-BalancedProfile}'S'{Apply-StrictProfile}'1'{New-PrivacySnapshot 'Personalization privacy'|Out-Null;Apply-PersonalizationPrivacy}'2'{New-PrivacySnapshot 'Activity privacy'|Out-Null;Apply-ActivityPrivacy}'3'{New-PrivacySnapshot 'Required diagnostics policy'|Out-Null;Apply-RequiredDiagnostics}'4'{New-PrivacySnapshot 'Browser telemetry policies'|Out-Null;Apply-BrowserTelemetryPolicies}'5'{New-PrivacySnapshot 'Location privacy'|Out-Null;Apply-LocationPrivacy}'6'{New-PrivacySnapshot 'Cloud search privacy'|Out-Null;Apply-CloudSearchPrivacy}'7'{New-PrivacySnapshot 'Delivery Optimization privacy'|Out-Null;Apply-DeliveryOptimizationPrivacy}'8'{New-PrivacySnapshot 'Strict telemetry services'|Out-Null;Apply-StrictTelemetryServiceProfile}'D'{Open-DnsManager}'U'{Restore-LatestSnapshot}'0'{break}default{Write-Status WARN 'Invalid selection.'}}}catch{Write-Status FAIL $_.Exception.Message}
    if($c -eq '0'){break};Write-Host '';Read-Host '  Press Enter to continue'|Out-Null
}
