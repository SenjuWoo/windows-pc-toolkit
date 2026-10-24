#requires -version 5.1
param([string]$DataRoot=(Join-Path $env:ProgramData 'WindowsPCToolkit\Suite'))
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:SuiteRoot=Split-Path $PSScriptRoot -Parent
$script:SuiteDataRoot=$DataRoot
$script:SuiteVersion='3.1.1'

function Write-SuiteDiagnostic {
    param([string]$Operation,[string]$Message,[string]$Level='Debug',[string]$RunId)
    if ($Level -eq 'Debug' -and $env:WINDOWS_PC_TOOLKIT_DEBUG -ne '1') { return }
    try {
        $directory=Join-Path $env:LOCALAPPDATA 'WindowsPCToolkit\Logs'
        [void][IO.Directory]::CreateDirectory($directory)
        $path=Join-Path $directory 'Suite.log'
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 5MB) { Move-Item -LiteralPath $path -Destination ($path+'.previous') -Force }
        $line=[ordered]@{Time=(Get-Date).ToString('o');Version=$script:SuiteVersion;Level=$Level;Operation=$Operation;RunId=$RunId;Message=$Message.Substring(0,[Math]::Min($Message.Length,4096))}
        [IO.File]::AppendAllText($path,($line | ConvertTo-Json -Compress)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    } catch { Write-Verbose "Diagnostic log unavailable: $($_.Exception.Message)" }
}
function Assert-SuiteUnlinkedPath {
    param([string]$Path)
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Toolkit state/package path contains a link: $current" }
        }
        $parent=Split-Path $current -Parent
        if ($parent -eq $current) { break }
        $current=$parent
    }
}

function Resolve-SuitePath {
    param([string[]]$Candidates)
    foreach ($relative in $Candidates) {
        $path=Join-Path $script:SuiteRoot $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
    throw "Toolkit file is missing: $($Candidates -join ', ')"
}
Import-Module (Resolve-SuitePath @('pc-gaming-optimizer\Modules\Optimizer.Core.psm1','Pc Gaming Optimizer\Modules\Optimizer.Core.psm1')) -Force -DisableNameChecking
. (Resolve-SuitePath @('pc-cleaner\PC_Cleaner.ps1','Pc Cleaner\PC_Cleaner.ps1')) -Action Library

function Get-SuiteDataRoot { $script:SuiteDataRoot }
function Get-SuiteVersion { $script:SuiteVersion }
function Get-SuiteIdentity { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function Assert-SuiteStatePermissions {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $trusted=@('S-1-5-18','S-1-5-32-544',(Get-SuiteIdentity))
    $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted) { throw 'Toolkit state has an untrusted owner. Do not use its reports or requests.' }
    $writes=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band $writes) -and $rule.IdentityReference.Value -notin $trusted) {
            throw 'Toolkit state is writable by another account. Existing data cannot be trusted; no changes were applied.'
        }
    }
}
function Initialize-SuiteState {
    Assert-SuiteUnlinkedPath $script:SuiteDataRoot
    if (-not (Test-Path -LiteralPath $script:SuiteDataRoot)) {
        [void][IO.Directory]::CreateDirectory($script:SuiteDataRoot)
        $acl=New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true,$false)
        foreach ($sid in @('S-1-5-18','S-1-5-32-544',(Get-SuiteIdentity)) | Select-Object -Unique) {
            $rule=New-Object Security.AccessControl.FileSystemAccessRule(
                (New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $script:SuiteDataRoot -AclObject $acl
    }
    Assert-SuiteStatePermissions $script:SuiteDataRoot
    foreach ($name in @('Runs','Requests','AppBackups')) {
        $path=Join-Path $script:SuiteDataRoot $name
        Assert-SuiteUnlinkedPath $path
        Assert-SuiteStatePermissions $path
        [void][IO.Directory]::CreateDirectory($path)
    }
}
function Save-SuiteJson {
    param([string]$Path,[object]$Value)
    Assert-SuiteUnlinkedPath $Path
    $state=[IO.Path]::GetFullPath($script:SuiteDataRoot).TrimEnd('\')+'\'
    if ([IO.Path]::GetFullPath($Path).StartsWith($state,[StringComparison]::OrdinalIgnoreCase)) {
        Assert-SuiteStatePermissions $script:SuiteDataRoot
        Assert-SuiteStatePermissions (Split-Path $Path -Parent)
        Assert-SuiteStatePermissions $Path
    }
    $json=$Value | ConvertTo-Json -Depth 16
    $null=$json | ConvertFrom-Json
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temporary,$json,(New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary,$Path,[NullString]::Value) }
    else { [IO.File]::Move($temporary,$Path) }
}
function New-SuiteRun {
    param([string]$Mode)
    Initialize-SuiteState
    $id=(Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $run=[pscustomobject]@{
        Schema=1; Id=$id; Version=$script:SuiteVersion; Computer=$env:COMPUTERNAME; UserSid=(Get-SuiteIdentity)
        Created=(Get-Date).ToString('o'); Mode=$Mode; Status='Running'; Message='Preparing'
        Registry=(New-Object Collections.ArrayList); Tasks=(New-Object Collections.ArrayList)
        Apps=(New-Object Collections.ArrayList); Features=(New-Object Collections.ArrayList); Steps=(New-Object Collections.ArrayList)
        Path=(Join-Path $script:SuiteDataRoot "Runs\$id.json")
    }
    Save-SuiteJson $run.Path $run
    return $run
}
function Enter-SuiteOperation {
    $mutex=New-Object Threading.Mutex($false,'Global\WindowsPCToolkit.SafeOperation')
    try { $entered=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $entered=$true }
    if (-not $entered) { $mutex.Dispose(); throw 'Another toolkit operation is running. Wait for it to finish.' }
    return $mutex
}
function Test-SuiteRegistryEqual {
    param($First,$Second)
    if ([bool]$First.Exists -ne [bool]$Second.Exists) { return $false }
    if (-not $First.Exists) { return $true }
    return ($First.Kind -eq $Second.Kind -and (ConvertTo-Json -InputObject $First.Value -Compress) -ceq (ConvertTo-Json -InputObject $Second.Value -Compress))
}
function Set-SuiteRegistry {
    param($Run,[string]$Path,[string]$Name,$Value,[string]$Kind='DWord',[switch]$Remove)
    $before=Get-RegistryValueState -Path $Path -Name $Name
    $desired=[pscustomobject]@{Path=$Path;Name=$Name;Exists=(-not $Remove);Kind=$Kind;Value=$Value}
    if (Test-SuiteRegistryEqual $before $desired) { return }
    $entry=[pscustomobject]@{Before=$before;After=$desired;Status='Pending'}
    [void]$Run.Registry.Add($entry)
    Save-SuiteJson $Run.Path $Run  # Persist recovery information BEFORE the write.
    if ($Remove) { Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop }
    else { Set-RegistryValueExact -Path $Path -Name $Name -Value $Value -Kind $Kind }
    $actual=Get-RegistryValueState -Path $Path -Name $Name
    if (-not (Test-SuiteRegistryEqual $actual $desired)) { throw "Read-back failed: $Path\$Name" }
    $entry.After=$actual; $entry.Status='Applied'
    Save-SuiteJson $Run.Path $Run
}
function Undo-SuiteRegistryEntry {
    param($Entry)
    Assert-SuiteRegistryEntry $Entry
    if ($Entry.Status -eq 'Restored') { return }
    $current=Get-RegistryValueState -Path $Entry.Before.Path -Name $Entry.Before.Name
    if (Test-SuiteRegistryEqual $current $Entry.Before) { $Entry.Status='Restored'; return }
    if (-not (Test-SuiteRegistryEqual $current $Entry.After)) { throw "Changed since optimization; kept your current value: $($Entry.Before.Path)\$($Entry.Before.Name)" }
    Restore-RegistryValueState $Entry.Before
    if (-not (Test-SuiteRegistryEqual (Get-RegistryValueState $Entry.Before.Path $Entry.Before.Name) $Entry.Before)) { throw 'Registry undo read-back failed.' }
    $Entry.Status='Restored'
}

function Assert-SuiteRegistryState {
    param($State)
    if (-not $State -or $State.Path -isnot [string] -or $State.Path -notmatch '^HK(?:CU|LM):\\' -or
        $State.Name -isnot [string] -or $State.Name.Length -gt 16383 -or $State.Name.Contains([string][char]0) -or $State.Exists -isnot [bool]) { throw 'Invalid registry backup target/state.' }
    if (-not $State.Exists) { return }
    if ($State.Kind -notin @('String','ExpandString','MultiString','Binary','DWord','QWord')) { throw 'Unsupported registry backup type.' }
    switch ($State.Kind) {
        { $_ -in @('String','ExpandString') } { if ($State.Value -isnot [string] -or $State.Value.Length -gt 1MB) { throw 'Invalid registry string backup.' } }
        'MultiString' { if ($State.Value -isnot [array] -or @($State.Value).Count -gt 4096 -or @($State.Value | Where-Object { $_ -isnot [string] -or $_.Length -gt 1MB }).Count) { throw 'Invalid registry multi-string backup.' } }
        'Binary' { if ($State.Value -isnot [array] -or @($State.Value).Count -gt 1MB -or @($State.Value | Where-Object { ($_ -isnot [int] -and $_ -isnot [long] -and $_ -isnot [byte]) -or $_ -lt 0 -or $_ -gt 255 }).Count) { throw 'Invalid registry binary backup.' } }
        'DWord' { if (($State.Value -isnot [int] -and $State.Value -isnot [long]) -or $State.Value -lt [int]::MinValue -or $State.Value -gt [int]::MaxValue) { throw 'Invalid registry DWORD backup.' } }
        'QWord' { if ($State.Value -isnot [int] -and $State.Value -isnot [long]) { throw 'Invalid registry QWORD backup.' } }
    }
}
function Assert-SuiteRegistryEntry {
    param($Entry)
    Assert-SuiteRegistryState $Entry.Before
    Assert-SuiteRegistryState $Entry.After
    if ($Entry.Before.Path -ne $Entry.After.Path -or $Entry.Before.Name -ne $Entry.After.Name -or $Entry.Status -notin @('Pending','Applied','Restored')) { throw 'Registry backup target/status changed.' }
}
function Get-SuiteRegistryUndoTargets {
    foreach ($action in Get-SuiteActionCatalog) { foreach ($target in $action.Targets) {
        [pscustomobject]@{Path=$target.Path;Name=$target.Name;Exists=$true;Kind=$(if ($target.ContainsKey('Kind')) { $target.Kind } else { 'DWord' });Value=$target.Value}
    } }
}
function Get-SuiteRegistryRemovalPaths {
    @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce','HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache')
}
function Get-SuiteConsumerAppNames {
    @('Microsoft.Copilot','Clipchamp.Clipchamp','Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection','Microsoft.People','Microsoft.Todos','Microsoft.WindowsFeedbackHub','Microsoft.YourPhone','Microsoft.ZuneMusic','Microsoft.ZuneVideo','MicrosoftCorporationII.MicrosoftFamily')
}
function Assert-SuiteUndoJournal {
    param($Run,[string]$Path)
    if ($Run.Id -isnot [string] -or $Run.Id -notmatch '^\d{8}_\d{6}_\d{3}_[a-f0-9]{8}$' -or [IO.Path]::GetFileNameWithoutExtension($Path) -cne $Run.Id -or
        $Run.Mode -notin @('Optimize','Startup','Debloat','RegistryCare','DNS','Repair') -or $Run.Status -notin @('Running','Completed','CompletedWithErrors','Failed','UndoNeedsAttention','Restored')) { throw 'Invalid recovery report identity/status.' }
    foreach ($property in @('Registry','Tasks','Apps')) {
        if ($Run.PSObject.Properties.Name -notcontains $property -or $Run.$property -isnot [array] -or @($Run.$property).Count -gt 4096) { throw 'Invalid or oversized recovery inventory.' }
    }
    $targets=@(Get-SuiteRegistryUndoTargets); $removals=@(Get-SuiteRegistryRemovalPaths)
    $seen=@{}
    foreach ($entry in $Run.Registry) {
        Assert-SuiteRegistryEntry $entry
        $id=$entry.Before.Path+[char]0+$entry.Before.Name
        if ($seen.ContainsKey($id)) { throw 'Recovery report contains duplicate registry targets.' }; $seen[$id]=$true
        if ($entry.After.Exists) {
            if (-not @($targets | Where-Object { $_.Path -eq $entry.After.Path -and $_.Name -eq $entry.After.Name -and (Test-SuiteRegistryEqual $_ $entry.After) }).Count) { throw 'Registry recovery target/value is outside toolkit settings.' }
        } elseif (-not $entry.Before.Exists -or $entry.Before.Path -notin $removals) { throw 'Registry removal backup is outside toolkit startup/MuiCache targets.' }
    }
    $seen=@{}
    foreach ($entry in $Run.Tasks) {
        if ($entry.Path -isnot [string] -or $entry.Path -notmatch '^\\' -or $entry.Path -notmatch '\\$' -or $entry.Path -like '\Microsoft\*' -or
            $entry.Name -isnot [string] -or -not $entry.Name -or $entry.Name -match '[\\/\x00-\x1f]' -or $entry.Enabled -isnot [bool] -or -not $entry.Enabled -or $entry.Status -notin @('Pending','Applied','Restored')) { throw 'Invalid or protected task recovery target.' }
        $id=$entry.Path+$entry.Name
        if ($seen.ContainsKey($id)) { throw 'Recovery report contains duplicate task targets.' }; $seen[$id]=$true
        if ($entry.Status -eq 'Restored' -or $Run.Status -eq 'Restored') { continue }
        $task=Get-SuiteTask $entry.Path $entry.Name
        if ($task.Author -match '(?i)Microsoft' -or -not @($task.Triggers | Where-Object { $null -ne $_ -and $_.CimClass.CimClassName -in @('MSFT_TaskLogonTrigger','MSFT_TaskBootTrigger') }).Count) { throw 'Task recovery target is no longer an optional startup task.' }
    }
    if ($Run.PSObject.Properties.Name -contains 'Features') {
        if ($Run.Features -isnot [array] -or @($Run.Features).Count -gt 1) { throw 'Invalid feature recovery inventory.' }
        foreach ($entry in $Run.Features) {
            if ($entry.Name -cne 'Recall' -or $entry.Before -cne 'Enabled' -or $entry.After -notin @('Disabled','DisabledWithPayloadRemoved','DisablePending') -or $entry.Status -notin @('Pending','Applied','Restored')) { throw 'Only the saved Recall feature transition can be restored.' }
        }
    }
    $seen=@{}
    foreach ($entry in $Run.Apps) {
        if ($entry.Name -notin @(Get-SuiteConsumerAppNames) -or $entry.Package -isnot [string] -or -not $entry.Package.StartsWith($entry.Name+'_',[StringComparison]::Ordinal) -or
            $entry.Package -match '[\\/:\x00-\x1f]' -or $entry.Status -notin @('Pending','Removed','Restored')) { throw 'Invalid or protected app recovery target.' }
        if ($seen.ContainsKey($entry.Name)) { throw 'Recovery report contains duplicate app targets.' }; $seen[$entry.Name]=$true
        $expected=[IO.Path]::GetFullPath((Join-Path $script:SuiteDataRoot ('AppBackups\'+$Run.Id+'\'+$entry.Package))).TrimEnd('\')
        if ([IO.Path]::GetFullPath($entry.Backup).TrimEnd('\') -ne $expected) { throw 'App backup does not belong to this operation/package.' }
        if ($entry.PSObject.Properties.Name -contains 'Files') { $null=Get-SuiteAppBackupInventory $entry }
    }
}
function Get-SuiteAppBackupInventory {
    param($Entry)
    if ($Entry.Files -isnot [array] -or -not @($Entry.Files).Count -or @($Entry.Files).Count -gt 100000) { throw 'Invalid app backup hash inventory.' }
    $backup=[IO.Path]::GetFullPath($Entry.Backup).TrimEnd('\')+'\'; $inventory=@{}
    foreach ($file in $Entry.Files) {
        if ($file.RelativePath -isnot [string] -or -not $file.RelativePath -or [IO.Path]::IsPathRooted($file.RelativePath) -or $file.RelativePath -match ':' -or $file.Hash -isnot [string] -or $file.Hash -cnotmatch '^[A-F0-9]{64}$') { throw 'Invalid app backup file/hash.' }
        $copy=[IO.Path]::GetFullPath((Join-Path $backup $file.RelativePath))
        if (-not $copy.StartsWith($backup,[StringComparison]::OrdinalIgnoreCase) -or $inventory.ContainsKey($copy)) { throw 'Duplicate or escaping app backup file path.' }
        $inventory[$copy]=$file.Hash
    }
    if (-not $inventory.ContainsKey((Join-Path $backup 'AppxManifest.xml'))) { throw 'App backup hash inventory omits its manifest.' }
    return $inventory
}

function Get-SuiteActionCatalog {
    @(
        [pscustomobject]@{Id='KeepLocalFolders';Name='Keep Desktop and Documents on this PC';Category='OneDrive';Default=$true;Detail='Block OneDrive from taking Desktop, Documents and Pictures (policy KFMBlockOptIn). Refuses while those folders still point at OneDrive. Does not move or delete files, and does not uninstall OneDrive.';Targets=@(
            @{Path='HKLM:\SOFTWARE\Policies\Microsoft\OneDrive';Name='KFMBlockOptIn';Value=1})},
        [pscustomobject]@{Id='GameMode';Name='Windows Game Mode';Category='Gaming';Default=$true;Detail='Enable Windows gaming scheduling. Keep GPU, drivers and fullscreen settings.';Targets=@(
            @{Path='HKCU:\Software\Microsoft\GameBar';Name='AllowAutoGameMode';Value=1},
            @{Path='HKCU:\Software\Microsoft\GameBar';Name='AutoGameModeEnabled';Value=1})},
        [pscustomobject]@{Id='Suggestions';Name='Less Windows bloat and promotion';Category='Debloat';Default=$true;Detail='Turn off suggested apps, silent promotional installs, tips and Settings recommendations.';Targets=@(
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SilentInstalledAppsEnabled';Value=0},
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SoftLandingEnabled';Value=0},
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SystemPaneSuggestionsEnabled';Value=0},
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SubscribedContent-338388Enabled';Value=0},
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SubscribedContent-338389Enabled';Value=0},
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SubscribedContent-353694Enabled';Value=0},
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SubscribedContent-353696Enabled';Value=0})},
        [pscustomobject]@{Id='Advertising';Name='Disable advertising personalization';Category='Privacy';Default=$true;Detail='Disable the Windows advertising ID and tailored experiences. Preserve diagnostic level and Insider.';Targets=@(
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo';Name='Enabled';Value=0},
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy';Name='TailoredExperiencesWithDiagnosticDataEnabled';Value=0})},
        [pscustomobject]@{Id='Activity';Name='Disable activity-history upload';Category='Privacy';Default=$true;Detail='Keep local app functionality while disabling activity publishing and upload.';Targets=@(
            @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';Name='PublishUserActivities';Value=0},
            @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';Name='UploadUserActivities';Value=0})},
        [pscustomobject]@{Id='Temp';Name='Clean aged temporary files';Category='Maintenance';Default=$true;Detail='Delete unlocked files older than 7 days in Windows Temp and your Temp folder. Temp-file deletion is not undoable.';Targets=@()},
        [pscustomobject]@{Id='DnsCache';Name='Refresh the DNS cache';Category='Network';Default=$true;Detail='Clear stale cached answers. Keep your DNS provider, VPN and adapter configuration.';Targets=@()},
        [pscustomobject]@{Id='Captures';Name='Disable background game recording';Category='Gaming';Default=$false;Detail='Turn off Windows background captures; leave Game Bar installed. Enable only if you do not use recordings.';Targets=@(
            @{Path='HKCU:\System\GameConfigStore';Name='GameDVR_Enabled';Value=0},
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR';Name='AppCaptureEnabled';Value=0})},
        [pscustomobject]@{Id='Animations';Name='Reduce desktop animations';Category='Appearance';Default=$false;Detail='Reduce taskbar and window animations; keep themes, accessibility and desktop composition.';Targets=@(
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='TaskbarAnimations';Value=0},
            @{Path='HKCU:\Control Panel\Desktop\WindowMetrics';Name='MinAnimate';Value='0';Kind='String'})},
        [pscustomobject]@{Id='Mouse';Name='Disable mouse acceleration';Category='Gaming';Default=$false;Detail='Use a consistent desktop pointer response. Many games already use raw input. Sign out to refresh.';Targets=@(
            @{Path='HKCU:\Control Panel\Mouse';Name='MouseSpeed';Value='0';Kind='String'},
            @{Path='HKCU:\Control Panel\Mouse';Name='MouseThreshold1';Value='0';Kind='String'},
            @{Path='HKCU:\Control Panel\Mouse';Name='MouseThreshold2';Value='0';Kind='String'})},
        [pscustomobject]@{Id='DeliveryCache';Name='Clear Delivery Optimization cache';Category='Maintenance';Default=$false;Detail='Use the Windows cache-cleanup API. Active downloads remain managed by Windows. Cache contents are not undoable.';Targets=@()},
        [pscustomobject]@{Id='Retrim';Name='ReTrim supported SSD volumes';Category='Storage';Default=$false;Detail='Ask Windows to ReTrim fixed NTFS/ReFS SSD volumes. Scheduled drive optimization usually covers this.';Targets=@()},
        [pscustomobject]@{Id='RegistryCare';Name='Repair dead startup and app-display entries';Category='Maintenance';Default=$true;Detail='Back up and remove entries with missing executables on ready fixed drives. No broad registry sweep or FPS claim.';Targets=@()}
        [pscustomobject]@{Id='Extensions';Name='Show file extensions';Category='Appearance';Default=$false;Detail='Show known file extensions in Explorer. Sign out to refresh Explorer settings.';Targets=@(
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='HideFileExt';Value=0})}
        [pscustomobject]@{Id='DarkMode';Name='Use dark Windows and app themes';Category='Appearance';Default=$false;Detail='Choose dark mode for Windows and apps that follow the Windows theme.';Targets=@(
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';Name='AppsUseLightTheme';Value=0},
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';Name='SystemUsesLightTheme';Value=0})}
        [pscustomobject]@{Id='TaskbarLeft';Name='Left-align the Windows 11 taskbar';Category='Appearance';Default=$false;MinBuild=22000;Detail='Choose left taskbar alignment. Sign out to refresh Explorer settings.';Targets=@(
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='TaskbarAl';Value=0})}
        [pscustomobject]@{Id='Widgets';Name='Hide the Widgets taskbar button';Category='Appearance';Default=$false;MinBuild=22000;Detail='Hide Widgets from the taskbar; keep WebView and the Windows components installed.';Targets=@(
            @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='TaskbarDa';Value=0})}
        [pscustomobject]@{Id='Recall';Name='Disable the Recall Windows feature';Category='AI debloat';Default=$true;MinBuild=26100;Detail='Disable Recall through Windows servicing when installed. Save feature state for undo; no forced restart. Recall snapshot data is not backed up.';Targets=@()}
        [pscustomobject]@{Id='Debloat';Name='Remove Copilot and optional consumer apps';Category='AI debloat';Default=$true;Detail='Remove this account''s allowlisted Copilot, Microsoft 365 hub, promotions and consumer apps after verified package backups. Preview lists installed apps; removal may delete their app data.';Targets=@()}
        [pscustomobject]@{Id='BrowserAI';Name='Disable built-in Edge AI models and APIs';Category='AI debloat';Default=$true;Detail='Block Edge built-in model downloads and website AI APIs where supported. Edge may delete its downloaded model; your separate AI apps/models are preserved. Policy undo does not restore model files.';Targets=@(
            @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge';Name='GenAILocalFoundationalModelSettings';Value=1},
            @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge';Name='BuiltInAIAPIsEnabled';Value=0})}
    )
}
function Get-SuiteTempRoots { @($env:TEMP,(Join-Path $env:SystemRoot 'Temp')) | Select-Object -Unique }
function Test-SuitePathWithoutLinks {
    param([string]$Path,[string]$Root)
    $full=[IO.Path]::GetFullPath($Path); $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (-not $full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)) { return $false }
    $current=$full
    while ($current -and $current.Length -ge $base.Length) {
        $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        if ($current -eq $base) { break }
        $current=Split-Path $current -Parent
    }
    return (-not (Test-IsProtectedPath $full))
}
function Get-SuiteOldTempFiles {
    param([string[]]$Roots=(Get-SuiteTempRoots),[int]$Days=7)
    Get-DisposableTempFiles -Roots $Roots -Days $Days
}
function Invoke-SuiteTempCleanup {
    $removed=0; $skipped=0; $bytes=[long]0; $cutoff=(Get-Date).AddDays(-7)
    # Windows can expose TEMP through an 8.3 user-folder alias. Normalize roots
    # with the same native path API used by the deletion boundary check.
    $roots=@(Get-SuiteTempRoots | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\')+'\' })
    foreach ($file in Get-SuiteOldTempFiles) {
        try {
            $root=$roots | Where-Object { [IO.Path]::GetFullPath($file.FullName).StartsWith($_,[StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
            if (-not $root -or -not (Test-SuitePathWithoutLinks $file.FullName $root)) { $skipped++; continue }
            $current=Get-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            if ($current.LastWriteTime -ge $cutoff -or $current.LastAccessTime -ge $cutoff) { $skipped++; continue }
            $length=$current.Length
            Remove-Item -LiteralPath $current.FullName -Force -ErrorAction Stop
            $bytes+=$length; $removed++
        } catch { $skipped++ }
    }
    return "$removed aged files removed; $skipped locked/recent/protected files skipped; $([math]::Round($bytes/1MB,1)) MB removed."
}
function Test-SuiteMissingExecutable {
    param([string]$Path)
    if (-not $Path -or $Path -notmatch '^[a-zA-Z]:\\' -or [IO.Path]::GetExtension($Path) -ne '.exe') { return $false }
    try {
        Assert-SuiteUnlinkedPath $Path
        $drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($Path))
        if (-not $drive.IsReady -or $drive.DriveType -ne 'Fixed') { return $false }
        [void][IO.File]::GetAttributes($Path)
        return $false
    } catch [IO.FileNotFoundException] { return $true }
    catch [IO.DirectoryNotFoundException] { return $drive.IsReady -and $drive.DriveType -eq 'Fixed' }
    catch { return $false }
}
function Get-SuiteStartupItems {
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $item=Get-Item -LiteralPath $key -ErrorAction Stop
        foreach ($name in $item.GetValueNames()) {
            $command=[string]$item.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $target=Get-CommandTargetPath $command
            [pscustomobject]@{Id=$key+'|'+$name;Kind='Startup';Name=$name;State='Configured';Target=$command;Path=$key;ValueName=$name;Missing=(Test-SuiteMissingExecutable $target);Selectable=$true}
        }
    }
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        foreach ($task in Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.Author -notmatch '(?i)Microsoft' }) {
            if (-not @($task.Triggers | Where-Object { $null -ne $_ -and $_.CimClass.CimClassName -in @('MSFT_TaskLogonTrigger','MSFT_TaskBootTrigger') }).Count) { continue }
            $commands=@($task.Actions | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'Execute') { $_.Execute } else { 'COM or custom task action' } })
            [pscustomobject]@{Id=$task.TaskPath+$task.TaskName;Kind='Task';Name=$task.TaskName;State=[string]$task.State;Target=($commands -join '; ');Path=$task.TaskPath;ValueName=$task.TaskName;Missing=$false;Selectable=$true}
        }
    }
}
function Get-SuiteAppCatalog {
    # Explicit consumer-app allowlist. Store, Xbox, Gaming Services, WebView,
    # frameworks, drivers and Windows components never enter this list.
    $names=@(Get-SuiteConsumerAppNames)
    foreach ($app in Get-AppxPackage -ErrorAction Stop | Where-Object { $names -contains $_.Name -and -not $_.IsFramework -and -not $_.NonRemovable }) {
        [pscustomobject]@{Id=$app.PackageFullName;Name=$app.Name;Version=[string]$app.Version;Location=$app.InstallLocation;Detail='Optional consumer app. Removal affects this user and its app data; package reinstall is available.'}
    }
}
function Get-SuiteTask {
    param([string]$Path,[string]$Name)
    $tasks=@(Get-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction Stop | Where-Object { $_.TaskPath -eq $Path -and $_.TaskName -eq $Name })
    if ($tasks.Count -ne 1) { throw 'The selected scheduled task changed or is missing. Refresh the list.' }
    return $tasks[0]
}
function Invoke-SuiteNative {
    param([string]$File,[string[]]$Arguments,[int[]]$SuccessCodes=@(0),[Text.Encoding]$OutputEncoding)
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$File; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    # SFC writes UTF-16LE without a BOM when redirected, including errors.
    if (-not $OutputEncoding -and [IO.Path]::GetFileName($File) -eq 'sfc.exe') { $OutputEncoding=[Text.Encoding]::Unicode }
    if ($OutputEncoding) { $psi.StandardOutputEncoding=$OutputEncoding; $psi.StandardErrorEncoding=$OutputEncoding }
    $psi.Arguments=(@($Arguments | ForEach-Object { '"'+(($_ -replace '(\\*)"','$1$1\"') -replace '(\\+)$','$1$1')+'"' }) -join ' ')
    $process=New-Object Diagnostics.Process; $process.StartInfo=$psi
    try {
        if (-not $process.Start()) { throw "Could not start $File" }
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $output=$stdout.Result+$stderr.Result; $code=$process.ExitCode
        if ($SuccessCodes -notcontains $code) { throw "$([IO.Path]::GetFileName($File)) exited with $code. $output" }
        [pscustomobject]@{ExitCode=$code;Output=$output.Trim();RestartRequired=($code -eq 3010)}
    } finally { $process.Dispose() }
}
function Get-SuiteHealth {
    $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cpu=Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $services=@(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object { $_.Name -in @('wuauserv','BITS','UsoSvc','WaaSMedicSvc','DoSvc','WinDefend','mpssvc','CryptSvc','AppXSvc','ClipSVC','GamingServices') } | Select-Object Name,StartMode,State)
    [pscustomobject]@{OS=$os.Caption;Build=$os.BuildNumber;CPU=$cpu.Name;RAMGB=[math]::Round($os.TotalVisibleMemorySize/1MB,1);FreeRAMGB=[math]::Round($os.FreePhysicalMemory/1MB,1);GPU=@(Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object Name,DriverVersion);Services=$services;UpdatesDisabled=@($services | Where-Object { $_.Name -in @('wuauserv','BITS','UsoSvc','WaaSMedicSvc') -and $_.StartMode -eq 'Disabled' }).Count;PowerScheme=(Get-ActivePowerSchemeGuid)}
}
function Get-SuitePreview {
    param([string[]]$ActionIds,[string[]]$StartupIds=@(),[string[]]$AppIds=@())
    $catalog=@(Get-SuiteActionCatalog)
    if ($null -eq $ActionIds) { $ActionIds=@(($catalog | Where-Object Default).Id) }
    foreach ($id in $ActionIds) {
        $action=$catalog | Where-Object Id -eq $id | Select-Object -First 1
        if (-not $action) { throw "Unknown action: $id" }
        $details=$action.Detail
        if ($id -eq 'Debloat') {
            $apps=@(Get-SuiteAppCatalog)
            $details+=' Installed: '+$(if ($apps.Count) { @($apps.Name) -join ', ' } else { 'None' })
        }
        if ($id -eq 'KeepLocalFolders') { $details+=' '+$(Get-SuiteOneDriveReport).Summary }
        [pscustomobject]@{Action=$action.Name;Category=$action.Category;Details=$details;Changes=@($action.Targets).Count}
    }
    if ($StartupIds.Count) {
        $items=@(Get-SuiteStartupItems)
        foreach ($id in $StartupIds | Select-Object -Unique) {
            $item=@($items | Where-Object Id -eq $id)
            if ($item.Count -ne 1) { throw 'A selected startup entry changed. Refresh the list.' }
            [pscustomobject]@{Action='Disable startup: '+$item[0].Name;Category='Reviewed startup';Details=$item[0].Target;Changes=1}
        }
    }
    if ($AppIds.Count) {
        $items=@(Get-SuiteAppCatalog)
        foreach ($id in $AppIds | Select-Object -Unique) {
            $item=@($items | Where-Object Id -eq $id)
            if ($item.Count -ne 1) { throw 'A selected app changed or is protected. Refresh the list.' }
            [pscustomobject]@{Action='Remove app: '+$item[0].Name;Category='Reviewed apps';Details='Verified package backup first; app data may be deleted.';Changes=1}
        }
    }
}
function Add-SuiteStep {
    param($Run,[string]$Action,[string]$Status,[string]$Message)
    [void]$Run.Steps.Add([pscustomobject]@{Action=$Action;Status=$Status;Message=$Message;Time=(Get-Date).ToString('o')})
    $Run.Message=$Message
    Save-SuiteJson $Run.Path $Run
    Write-SuiteDiagnostic -Operation $Action -Message $Message -RunId $Run.Id -Level $(if ($Status -eq 'Failed') { 'Error' } else { 'Debug' })
}
function Invoke-SuiteRun {
    param([string[]]$ActionIds,[string[]]$StartupIds=@(),[string[]]$AppIds=@(),[scriptblock]$Progress)
    Assert-Administrator
    $catalog=@(Get-SuiteActionCatalog)
    if ($null -eq $ActionIds) { $ActionIds=@(($catalog | Where-Object Default).Id) }
    $null=Get-SuitePreview $ActionIds
    if ($ActionIds -contains 'Debloat' -and -not $PSBoundParameters.ContainsKey('AppIds')) { $AppIds=@(Get-SuiteAppCatalog | ForEach-Object Id) }
    $AppIds=@($AppIds | Select-Object -Unique)
    if ($StartupIds.Count) {
        $startup=@(Get-SuiteStartupItems)
        foreach ($id in $StartupIds) { if (@($startup | Where-Object Id -eq $id).Count -ne 1) { throw 'A selected startup entry changed. Refresh the list.' } }
    }
    if ($AppIds.Count) {
        $apps=@(Get-SuiteAppCatalog)
        foreach ($id in $AppIds) { if (@($apps | Where-Object Id -eq $id).Count -ne 1) { throw 'A selected app changed or is protected. Refresh the list.' } }
    }
    $lock=Enter-SuiteOperation
    try {
        $run=New-SuiteRun 'Optimize'
        foreach ($id in $ActionIds | Select-Object -Unique) {
            $action=$catalog | Where-Object Id -eq $id | Select-Object -First 1
            $run.Message="Running: $($action.Name)"; Save-SuiteJson $run.Path $run
            if ($Progress) { & $Progress $run }
            $start=$run.Registry.Count
            try {
                if ($action.PSObject.Properties.Name -contains 'MinBuild') {
                    $build=[int](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).BuildNumber
                    if ($build -lt $action.MinBuild) { Add-SuiteStep $run $action.Name 'Skipped' "Requires Windows build $($action.MinBuild) or newer."; continue }
                }
                if ($id -eq 'KeepLocalFolders') {
                    $null=Invoke-SuiteKnownFolderLock -Run $run
                    Add-SuiteStep $run $action.Name 'Applied' 'Known folders stay on this PC. OneDrive cannot take Desktop, Documents and Pictures. No files were moved or deleted.'
                    continue
                }
                foreach ($target in $action.Targets) {
                    $kind=if ($target.ContainsKey('Kind')) { $target.Kind } else { 'DWord' }
                    Set-SuiteRegistry $run $target.Path $target.Name $target.Value $kind
                }
                $message='Settings saved and verified. A sign-out may be needed to refresh Windows.'
                switch ($id) {
                    'Temp' { $message=Invoke-SuiteTempCleanup }
                    'DnsCache' { Clear-DnsClientCache -ErrorAction Stop; $message='DNS cache refreshed. Adapter settings preserved.' }
                    'Debloat' {
                        if (-not $AppIds.Count) { Add-SuiteStep $run $action.Name 'Skipped' 'No optional consumer apps selected or installed.' }
                        else { Add-SuiteStep $run $action.Name 'Queued' 'Consumer app selections validated. Verified backup and removal follows below.' }
                        continue
                    }
                    'Recall' {
                        foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
                            if (Test-Path -LiteralPath $key) { throw 'Finish the pending Windows restart before changing the Recall feature.' }
                        }
                        $feature=Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object FeatureName -eq 'Recall' | Select-Object -First 1
                        if (-not $feature -or [string]$feature.State -in @('Disabled','DisabledWithPayloadRemoved')) { Add-SuiteStep $run $action.Name 'Skipped' 'Recall is absent or already disabled.'; continue }
                        if ([string]$feature.State -ne 'Enabled') { throw 'Recall has a pending servicing change. Restart Windows first.' }
                        $entry=[pscustomobject]@{Name='Recall';Before='Enabled';After='Disabled';Status='Pending'}
                        [void]$run.Features.Add($entry); Save-SuiteJson $run.Path $run
                        $result=Disable-WindowsOptionalFeature -Online -FeatureName Recall -NoRestart -ErrorAction Stop
                        $actual=[string](Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction Stop).State
                        if ($actual -notin @('Disabled','DisabledWithPayloadRemoved','DisablePending')) { throw 'Recall disable read-back failed.' }
                        $entry.After=if ($actual -eq 'DisablePending') { 'Disabled' } else { $actual }; $entry.Status='Applied'; Save-SuiteJson $run.Path $run
                        $message='Recall disabled through Windows servicing. Feature payload kept for undo; snapshot data is not restored.'
                        if ($result.RestartNeeded -or $actual -eq 'DisablePending') { $message+=' Restart Windows to finish.' }
                    }
                    'DeliveryCache' { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; $message='Windows Delivery Optimization cache-cleanup request completed.' }
                    'Retrim' {
                        $count=0
                        $physical=@(Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.MediaType -eq 'SSD' -and -not [string]::IsNullOrWhiteSpace($_.SerialNumber) })
                        foreach ($disk in Get-Disk -ErrorAction Stop) {
                            if ([string]::IsNullOrWhiteSpace($disk.SerialNumber)) { continue }
                            $matches=@($physical | Where-Object { $_.SerialNumber.Trim() -eq $disk.SerialNumber.Trim() })
                            if ($matches.Count -ne 1) { continue }
                            foreach ($volume in @(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop | Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.FileSystem -in @('NTFS','ReFS') })) {
                                Optimize-Volume -DriveLetter $volume.DriveLetter -ReTrim -ErrorAction Stop; $count++
                            }
                        }
                        $message="ReTrim completed on $count supported SSD volumes. Other volumes preserved."
                    }
                    'RegistryCare' {
                        $count=0
                        foreach ($item in Get-SuiteStartupItems | Where-Object { $_.Kind -eq 'Startup' -and $_.Missing }) {
                            $current=Get-RegistryValueState $item.Path $item.ValueName
                            if ($current.Exists -and (Test-SuiteMissingExecutable (Get-CommandTargetPath ([string]$current.Value)))) { Set-SuiteRegistry $run $item.Path $item.ValueName $null -Remove; $count++ }
                        }
                        foreach ($issue in Get-RegistryIssues | Where-Object { $_.Category -eq 'Stale MuiCache entries' }) {
                            if (Test-SuiteMissingExecutable $issue.Display) { Set-SuiteRegistry $run $issue.Key $issue.Name $null -Remove; $count++ }
                        }
                        $message="$count dead startup/MuiCache values removed with exact backups. App registrations and uninstall keys preserved."
                    }
                }
                Add-SuiteStep $run $action.Name 'Applied' $message
            } catch {
                $errorText=$_.Exception.Message
                for ($index=$run.Registry.Count-1; $index -ge $start; $index--) {
                    try { Undo-SuiteRegistryEntry $run.Registry[$index] } catch { $errorText+=' Rollback: '+$_.Exception.Message }
                }
                Add-SuiteStep $run $action.Name 'Failed' $errorText
            }
            if ($Progress) { & $Progress $run }
        }
        if ($StartupIds.Count) {
            $run.Message='Applying reviewed startup selections'; if ($Progress) { & $Progress $run }
            try { $null=Invoke-SuiteStartupDisable -Ids $StartupIds -Run $run } catch { Add-SuiteStep $run 'Reviewed startup items' 'Failed' $_.Exception.Message }
        }
        if ($AppIds.Count) {
            $run.Message='Backing up and removing selected consumer apps'; if ($Progress) { & $Progress $run }
            try { $null=Invoke-SuiteAppRemoval -Ids $AppIds -Run $run } catch { Add-SuiteStep $run 'Reviewed app removal' 'Failed' $_.Exception.Message }
        }
        $run.Status=if (@($run.Steps | Where-Object Status -eq 'Failed').Count) { 'CompletedWithErrors' } else { 'Completed' }
        $run.Message="$($run.Status): $(@($run.Steps | Where-Object Status -eq 'Applied').Count) actions completed. Report: $($run.Path)"
        Save-SuiteJson $run.Path $run
        return $run
    } finally { $lock.ReleaseMutex(); $lock.Dispose() }
}
function Invoke-SuiteStartupDisable {
    param([string[]]$Ids,$Run)
    Assert-Administrator
    $available=@(Get-SuiteStartupItems)
    if (-not $Ids) { throw 'Select a startup item first.' }
    foreach ($id in $Ids) { if (@($available | Where-Object Id -eq $id).Count -ne 1) { throw 'Startup selection changed. Refresh the list.' } }
    $ownedRun=($null -eq $Run); $lock=$null
    if ($ownedRun) { $lock=Enter-SuiteOperation }
    try {
        if ($ownedRun) { $run=New-SuiteRun 'Startup' }
        foreach ($item in $available | Where-Object { $Ids -contains $_.Id }) {
            try {
                if ($item.Kind -eq 'Startup') { Set-SuiteRegistry $run $item.Path $item.ValueName $null -Remove }
                else {
                    $task=Get-SuiteTask $item.Path $item.ValueName
                    if (-not $task.Settings.Enabled) { Add-SuiteStep $run $item.Name 'Skipped' 'Startup task was already disabled.'; continue }
                    $entry=[pscustomobject]@{Path=$item.Path;Name=$item.ValueName;Enabled=[bool]$task.Settings.Enabled;Status='Pending'}
                    [void]$run.Tasks.Add($entry); Save-SuiteJson $run.Path $run
                    Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
                    if ((Get-SuiteTask $item.Path $item.ValueName).Settings.Enabled) { throw 'Task disable verification failed.' }
                    $entry.Status='Applied'
                }
                Add-SuiteStep $run $item.Name 'Applied' 'Startup item disabled; original state saved.'
            } catch { Add-SuiteStep $run $item.Name 'Failed' $_.Exception.Message }
        }
        $run.Status=if (@($run.Steps | Where-Object Status -eq 'Failed').Count) { 'CompletedWithErrors' } else { 'Completed' }
        Save-SuiteJson $run.Path $run; return $run
    } finally { if ($lock) { $lock.ReleaseMutex(); $lock.Dispose() } }
}
function Invoke-SuiteAppRemoval {
    param([string[]]$Ids,$Run)
    Assert-Administrator
    $available=@(Get-SuiteAppCatalog)
    if (-not $Ids) { throw 'Select optional consumer apps first.' }
    foreach ($id in $Ids) { if (@($available | Where-Object Id -eq $id).Count -ne 1) { throw 'App selection changed or contains a protected package. Refresh the list.' } }
    $ownedRun=($null -eq $Run); $lock=$null
    if ($ownedRun) { $lock=Enter-SuiteOperation }
    try {
        if ($ownedRun) { $run=New-SuiteRun 'Debloat' }
        foreach ($app in $available | Where-Object { $Ids -contains $_.Id }) {
            try {
                $source=Get-Item -LiteralPath $app.Location -ErrorAction Stop
                Assert-SuiteUnlinkedPath $source.FullName
                if ($source.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Package folder is a link; kept the app.' }
                if (@(Get-ChildItem -LiteralPath $source.FullName -Recurse -Force -ErrorAction Stop | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Package contains linked files/folders; kept the app.' }
                $backup=Join-Path $script:SuiteDataRoot ('AppBackups\'+$run.Id+'\'+$app.Id)
                Assert-SuiteUnlinkedPath $backup
                [void][IO.Directory]::CreateDirectory($backup)
                # robocopy preserves long package paths and skips junctions. Codes 0-7 are success.
                $null=Invoke-SuiteNative "$env:SystemRoot\System32\robocopy.exe" @($app.Location,$backup,'/E','/XJ','/R:0','/W:0','/NFL','/NDL','/NJH','/NJS') @(0,1,2,3,4,5,6,7)
                if (-not (Test-Path -LiteralPath (Join-Path $backup 'AppxManifest.xml'))) { throw 'Package backup is incomplete; kept the app.' }
                $hashes=@(foreach ($file in Get-ChildItem -LiteralPath $source.FullName -Recurse -File -Force -ErrorAction Stop) {
                    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'A package file is a link; kept the app.' }
                    $relative=$file.FullName.Substring($source.FullName.TrimEnd('\').Length).TrimStart('\')
                    $copy=Join-Path $backup $relative
                    if (-not (Test-Path -LiteralPath $copy) -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash) { throw 'Package backup verification failed; kept the app.' }
                    [pscustomobject]@{RelativePath=$relative;Hash=(Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash}
                })
                $entry=[pscustomobject]@{Name=$app.Name;Package=$app.Id;Backup=$backup;Files=$hashes;Status='Pending'}
                [void]$run.Apps.Add($entry); Save-SuiteJson $run.Path $run
                Remove-AppxPackage -Package $app.Id -ErrorAction Stop
                if (Get-AppxPackage -Name $app.Name -ErrorAction Stop) { throw 'Package is still installed.' }
                $entry.Status='Removed'; Add-SuiteStep $run $app.Name 'Applied' 'Removed for this user. Package reinstall backup saved; app data is not restored by reinstall.'
            } catch { Add-SuiteStep $run $app.Name 'Failed' $_.Exception.Message }
        }
        $run.Status=if (@($run.Steps | Where-Object Status -eq 'Failed').Count) { 'CompletedWithErrors' } else { 'Completed' }
        Save-SuiteJson $run.Path $run; return $run
    } finally { if ($lock) { $lock.ReleaseMutex(); $lock.Dispose() } }
}
function Get-SuiteHistory {
    $directory=Join-Path $script:SuiteDataRoot 'Runs'
    if (-not (Test-Path -LiteralPath $directory)) { return }
    Assert-SuiteUnlinkedPath $directory
    Assert-SuiteStatePermissions $script:SuiteDataRoot
    Assert-SuiteStatePermissions $directory
    foreach ($file in Get-ChildItem -LiteralPath $directory -Filter '*.json' -File | Sort-Object Name -Descending) {
        try {
            Assert-SuiteUnlinkedPath $file.FullName
            Assert-SuiteStatePermissions $file.FullName
            $run=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($run.Schema -eq 1 -and $run.Computer -eq $env:COMPUTERNAME -and $run.UserSid -eq (Get-SuiteIdentity)) { $run.Path=$file.FullName; $run }
        } catch { Write-Warning "Unreadable report: $($file.Name)" }
    }
}
function Invoke-SuiteUndo {
    param([string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    $root=[IO.Path]::GetFullPath((Join-Path $script:SuiteDataRoot 'Runs')).TrimEnd('\')+'\'
    if (-not $full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($full) -ne '.json') { throw 'Select a report from this toolkit history.' }
    Assert-SuiteUnlinkedPath $full
    Assert-SuiteStatePermissions $script:SuiteDataRoot
    Assert-SuiteStatePermissions (Split-Path $full -Parent)
    Assert-SuiteStatePermissions $full
    if ((Get-Item -LiteralPath $full -ErrorAction Stop).Length -gt 16MB) { throw 'Recovery report is too large.' }
    $run=Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($run.Schema -ne 1 -or $run.Computer -ne $env:COMPUTERNAME -or $run.UserSid -ne (Get-SuiteIdentity)) { throw 'This backup belongs to another computer/user or uses an unsupported schema.' }
    if ($run.Mode -eq 'OneDriveFolders') { throw 'OneDrive folder locations are not put back. The report lists the old paths. No files were deleted.' }
    Assert-Administrator
    Assert-SuiteUndoJournal $run $full
    if ($run.Status -eq 'Restored') { $run.Message='This operation was already restored. Current settings have been preserved.'; return $run }
    if (-not (@($run.Registry).Count + @($run.Tasks).Count + @($run.Apps).Count) -and
        -not ($run.PSObject.Properties.Name -contains 'Features' -and @($run.Features).Count) -and
        -not ($run.PSObject.Properties.Name -contains 'DnsBackup' -and $run.DnsBackup)) { throw 'This report contains no reversible changes. Repair and cache/temp deletion cannot be undone.' }
    $run.Path=$full
    $lock=Enter-SuiteOperation
    try {
        $errors=New-Object Collections.ArrayList
        if ($run.PSObject.Properties.Name -contains 'DnsBackup') {
            try {
                . (Resolve-SuitePath @('dns-encrypted-doh\DNS_Manager.ps1','Pc Privacy Guard\Optional DNS\DNS_Manager.ps1')) -Action Library
                Restore-Snapshot -Path $run.DnsBackup
            } catch { [void]$errors.Add($_.Exception.Message) }
        }
        for ($index=@($run.Registry).Count-1; $index -ge 0; $index--) {
            try { Undo-SuiteRegistryEntry $run.Registry[$index] } catch { [void]$errors.Add($_.Exception.Message) }
            Save-SuiteJson $full $run
        }
        foreach ($entry in @($run.Tasks)) {
            try {
                if ($entry.Status -eq 'Restored') { continue }
                $task=Get-SuiteTask $entry.Path $entry.Name
                if ($entry.Enabled -and -not $task.Settings.Enabled) { Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null }
                if ([bool](Get-SuiteTask $entry.Path $entry.Name).Settings.Enabled -ne [bool]$entry.Enabled) { throw 'Task was changed after optimization; current state preserved.' }
                $entry.Status='Restored'
            } catch { [void]$errors.Add($_.Exception.Message) }
            Save-SuiteJson $full $run
        }
        foreach ($entry in @($run.Apps)) {
            try {
                if ($entry.Status -eq 'Restored') { continue }
                if (-not (Get-AppxPackage -Name $entry.Name -ErrorAction Stop)) {
                    $backup=[IO.Path]::GetFullPath($entry.Backup).TrimEnd('\')+'\'
                    $backupRoot=[IO.Path]::GetFullPath((Join-Path $script:SuiteDataRoot 'AppBackups')).TrimEnd('\')+'\'
                    if (-not $backup.StartsWith($backupRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'App backup is outside toolkit storage.' }
                    Assert-SuiteUnlinkedPath $backup
                    if (@(Get-ChildItem -LiteralPath $backup -Recurse -Force -ErrorAction Stop | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'App backup contains links; use Microsoft Store to reinstall.' }
                    if ($entry.PSObject.Properties.Name -notcontains 'Files' -or -not @($entry.Files).Count) { throw 'Legacy app backup has no saved hashes. Reinstall this app using Microsoft Store.' }
                    $inventory=Get-SuiteAppBackupInventory $entry
                    $files=@(Get-ChildItem -LiteralPath $backup -Recurse -File -Force -ErrorAction Stop)
                    if ($files.Count -ne $inventory.Count) { throw 'App backup contents changed; use Microsoft Store to reinstall.' }
                    foreach ($file in $files) {
                        $copy=[IO.Path]::GetFullPath($file.FullName)
                        if (-not $inventory.ContainsKey($copy)) { throw 'App backup contains an unrecorded file.' }
                        Assert-SuiteUnlinkedPath $copy
                        Assert-SuiteStatePermissions $copy
                        if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256 -ErrorAction Stop).Hash -cne $inventory[$copy]) { throw 'App backup hash changed; use Microsoft Store to reinstall.' }
                    }
                    Add-AppxPackage -Register (Join-Path $entry.Backup 'AppxManifest.xml') -DisableDevelopmentMode -ErrorAction Stop
                }
                if (-not (Get-AppxPackage -Name $entry.Name -ErrorAction Stop)) { throw "Reinstall failed: $($entry.Name). Use Microsoft Store to reinstall." }
                $entry.Status='Restored'
            } catch { [void]$errors.Add($_.Exception.Message) }
            Save-SuiteJson $full $run
        }
        if ($run.PSObject.Properties.Name -contains 'Features') {
            foreach ($entry in @($run.Features)) {
                try {
                    if ($entry.Status -eq 'Restored') { continue }
                    $current=[string](Get-WindowsOptionalFeature -Online -FeatureName $entry.Name -ErrorAction Stop).State
                    if ($current -eq $entry.Before) { $entry.Status='Restored'; continue }
                    if ($current -in @('EnablePending','DisablePending')) { throw 'Restart Windows before restoring the Recall feature.' }
                    if ($current -ne $entry.After -and -not ($entry.After -eq 'DisablePending' -and $current -eq 'Disabled')) { throw 'Windows feature changed since optimization; current state preserved.' }
                    $result=Enable-WindowsOptionalFeature -Online -FeatureName $entry.Name -NoRestart -ErrorAction Stop
                    $actual=[string](Get-WindowsOptionalFeature -Online -FeatureName $entry.Name -ErrorAction Stop).State
                    if ($actual -eq 'EnablePending' -or $result.RestartNeeded) { throw 'Recall restore requested. Restart Windows, then retry undo to verify.' }
                    if ($actual -ne $entry.Before) { throw 'Recall restore read-back failed.' }
                    $entry.Status='Restored'
                } catch { [void]$errors.Add($_.Exception.Message) }
                Save-SuiteJson $full $run
            }
        }
        $run.Status=if ($errors.Count) { 'UndoNeedsAttention' } else { 'Restored' }
        $run.Message=if ($errors.Count) { $errors -join "`n" } else { 'Settings/startup restored and checked. Deleted temp/cache files and removed app data are not restored.' }
        Save-SuiteJson $full $run; return $run
    } finally { $lock.ReleaseMutex(); $lock.Dispose() }
}

function Invoke-SuiteRepair {
    param([scriptblock]$Progress)
    Assert-Administrator
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path -LiteralPath $key) { throw 'Finish the pending Windows restart before running system repair.' }
    }
    $lock=Enter-SuiteOperation
    try {
        $run=New-SuiteRun 'Repair'
        try { Enable-StayAwake } catch { Add-SuiteStep $run 'Stay awake' 'Warning' $_.Exception.Message }
        foreach ($step in @(
            @{Name='DISM component-store repair';File='dism.exe';Args=@('/Online','/Cleanup-Image','/RestoreHealth','/NoRestart')},
            @{Name='SFC system-file scan';File='sfc.exe';Args=@('/scannow')})) {
            $run.Message='Running: '+$step.Name; Save-SuiteJson $run.Path $run
            if ($Progress) { & $Progress $run }
            try {
                $native=Invoke-SuiteNative (Join-Path "$env:SystemRoot\System32" $step.File) $step.Args @(0,3010)
                Add-SuiteStep $run $step.Name 'Completed' ($native.Output+$(if ($native.RestartRequired) { ' Restart required.' } else { '' }))
                if ($native.RestartRequired) { Add-SuiteStep $run 'Remaining repair commands' 'Skipped' 'Restart Windows before continuing system repair.'; break }
            } catch { Add-SuiteStep $run $step.Name 'Failed' $_.Exception.Message; break }
        }
        $run.Status=if (@($run.Steps | Where-Object Status -eq 'Failed').Count) { 'CompletedWithErrors' } else { 'Completed' }
        $run.Message=if ($run.Status -eq 'CompletedWithErrors') { 'Repair stopped after a failed command. Review its output below or in Recovery. No automatic restart.' } else { 'Repair commands finished. Review the saved DISM/SFC output for the corruption verdict. No automatic restart.' }
        Save-SuiteJson $run.Path $run; return $run
    } finally {
        try { Disable-StayAwake } catch { Write-Warning $_.Exception.Message }
        finally { $lock.ReleaseMutex(); $lock.Dispose() }
    }
}

# OneDrive preflight reads legacy paths and modern local-folder aliases before
# offering a policy lock or uninstall shortcut. It never migrates user files.
function Get-SuiteKnownFolderCatalog {
    @(
        [pscustomobject]@{Folder='Desktop';ValueName='Desktop';Relative='Desktop';Alias=''},
        [pscustomobject]@{Folder='Documents';ValueName='Personal';Relative='Documents';Alias='{F42EE2D3-909F-4907-8871-4C22FC0BF756}'},
        [pscustomobject]@{Folder='Pictures';ValueName='My Pictures';Relative='Pictures';Alias='{0DDD015D-B06C-45D5-8C4C-F59713854639}'},
        [pscustomobject]@{Folder='Music';ValueName='My Music';Relative='Music';Alias='{A0C69A99-21C8-4671-8703-7934162FCF1D}'},
        [pscustomobject]@{Folder='Videos';ValueName='My Video';Relative='Videos';Alias='{35286A68-3C57-41A1-BBB1-0EAE73D76C95}'}
    )
}
function Get-SuiteOneDriveAccountRoots {
    $roots=@()
    $key='HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (-not (Test-Path -LiteralPath $key)) { return @() }
    foreach ($account in @(Get-ChildItem -LiteralPath $key -ErrorAction Stop)) {
        $value=(Get-Item -LiteralPath $account.PSPath -ErrorAction Stop).GetValue('UserFolder')
        if ($value -is [string] -and $value.Trim()) { $roots+=$value.Trim() }
    }
    return @($roots)
}
function Get-SuiteOneDriveExecutable {
    $candidates=New-Object Collections.Generic.List[string]
    [void]$candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'))
    if ($env:ProgramFiles) { [void]$candidates.Add((Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')) }
    $programFilesX86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) { [void]$candidates.Add((Join-Path $programFilesX86 'Microsoft OneDrive\OneDrive.exe')) }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return ''
}
function Test-SuiteOneDrivePath {
    param([string]$Expanded,[string[]]$Roots)
    if (-not $Expanded) { return $false }
    $full=$Expanded.TrimEnd('\')
    foreach ($root in @($Roots)) {
        if (-not $root) { continue }
        $prefix=$root.TrimEnd('\')
        if ($full.Equals($prefix,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($prefix+'\',[StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    foreach ($segment in $full.Split('\')) {
        if ($segment -match '^(?i)OneDrive($| - .+)$') { return $true }
    }
    return $false
}
function Test-SuiteCloudOnlyAttribute {
    param([int]$Attributes)
    # Win32 FILE_ATTRIBUTE_RECALL_ON_OPEN and FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS.
    return (($Attributes -band 0x40000) -ne 0) -or (($Attributes -band 0x400000) -ne 0)
}
function Get-SuiteCloudOnlyCount {
    param([string]$Path,[ValidateRange(1,100000)][int]$Limit=2000)
    $result=[pscustomobject]@{Count=0;Capped=$false;Incomplete=$false}
    $seen=0
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) { $result.Incomplete=$true; return $result }
        $rootItem=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Test-SuiteCloudOnlyAttribute ([int]$rootItem.Attributes))) { $result.Incomplete=$true; return $result }
    } catch { $result.Incomplete=$true; return $result }
    $pending=New-Object Collections.Generic.Queue[string]
    $pending.Enqueue($Path)
    while ($pending.Count -gt 0 -and -not $result.Capped) {
        $directory=$pending.Dequeue()
        try { $entries=@(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop | Select-Object -First ($Limit-$seen)) } catch { $result.Incomplete=$true; continue }
        foreach ($entry in $entries) {
            $seen++
            $recall=Test-SuiteCloudOnlyAttribute ([int]$entry.Attributes)
            $linked=[bool]($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)
            # Cloud files are reparse points too. Count their metadata before skipping links;
            # enumerating linked or virtual directories can fetch remote data, so never follow them.
            if ($entry.PSIsContainer) {
                if ($linked -or $recall) { $result.Incomplete=$true }
                else { $pending.Enqueue($entry.FullName) }
            } elseif ($recall) { $result.Count++ }
            elseif ($linked) { $result.Incomplete=$true }
            if ($seen -ge $Limit) { $result.Capped=$true; $result.Incomplete=$true; break }
        }
    }
    return $result
}
function Get-SuiteFolderClass {
    param([string]$Raw,[string]$ProfilePath,[string]$Relative,[string[]]$Roots,[string]$Kind='String')
    if ([string]::IsNullOrWhiteSpace($Raw)) { return 'Missing' }
    if ($Kind -notin @('String','ExpandString')) { return 'Unknown' }
    try {
        $expanded=[Environment]::ExpandEnvironmentVariables($Raw)
        if ($expanded -match '%[^%]+%' -or $expanded -notmatch '^[A-Za-z]:[\\/]') { return 'Unknown' }
        $expanded=[IO.Path]::GetFullPath($expanded).TrimEnd('\')
        if (Test-SuiteOneDrivePath $expanded $Roots) { return 'OneDrive' }
        # A lexical local path is insufficient: a link can lead straight back into cloud storage.
        Assert-SuiteUnlinkedPath $expanded
        $item=Get-Item -LiteralPath $expanded -Force -ErrorAction Stop
        if (-not $item.PSIsContainer) { return 'Unknown' }
        $default=[IO.Path]::GetFullPath((Join-Path $ProfilePath $Relative)).TrimEnd('\')
        if ($expanded.Equals($default,[StringComparison]::OrdinalIgnoreCase)) { return 'Local' }
        return 'Custom'
    } catch { return 'Unknown' }
}
function Get-SuiteOneDriveReport {
    param(
        [string]$UserShellKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders',
        [string]$ShellKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
        [string]$PolicyKey='HKLM:\SOFTWARE\Policies\Microsoft\OneDrive',
        [string]$ProfilePath=$env:USERPROFILE,
        [string[]]$OneDriveRoots,
        [string]$OneDriveExecutable,
        [switch]$CountCloudOnly,
        [int]$CloudLimit=2000
    )
    if (-not $PSBoundParameters.ContainsKey('OneDriveRoots')) { $OneDriveRoots=@(Get-SuiteOneDriveAccountRoots) }
    if (-not $PSBoundParameters.ContainsKey('OneDriveExecutable')) { $OneDriveExecutable=[string](Get-SuiteOneDriveExecutable) }
    $folders=New-Object Collections.Generic.List[object]
    foreach ($known in @(Get-SuiteKnownFolderCatalog)) {
        $userState=Get-RegistryValueState -Path $UserShellKey -Name $known.ValueName
        $shellState=Get-RegistryValueState -Path $ShellKey -Name $known.ValueName
        $userRaw=$(if ($userState.Exists) { [string]$userState.Value } else { '' })
        $shellRaw=$(if ($shellState.Exists) { [string]$shellState.Value } else { '' })
        $userClass=Get-SuiteFolderClass $userRaw $ProfilePath $known.Relative $OneDriveRoots $userState.Kind
        $shellClass=Get-SuiteFolderClass $shellRaw $ProfilePath $known.Relative $OneDriveRoots $shellState.Kind
        $aliasClasses=@(); $aliasNotes=@()
        if ($known.Alias) {
            foreach ($key in @($UserShellKey,$ShellKey)) {
                $aliasState=Get-RegistryValueState -Path $key -Name $known.Alias
                if (-not $aliasState.Exists) { continue }
                $class=Get-SuiteFolderClass ([string]$aliasState.Value) $ProfilePath $known.Relative $OneDriveRoots $aliasState.Kind
                $aliasClasses+=$class
                if ($class -notin @('Local','Custom')) { $aliasNotes+='Additional Windows location needs attention: '+[string]$aliasState.Value }
            }
        }
        $location=$(if ($userRaw) { [Environment]::ExpandEnvironmentVariables($userRaw) } else { '' })
        $cloud=[pscustomobject]@{Count=0;Capped=$false;Incomplete=$false}
        if ($CountCloudOnly -and $userClass -eq 'OneDrive' -and $location) { $cloud=Get-SuiteCloudOnlyCount -Path $location -Limit $CloudLimit }
        $status=switch ($userClass) {
            'Local' { if ($shellClass -eq 'OneDrive') { 'Explorer cache still points at OneDrive' } elseif ($shellClass -eq 'Unknown') { 'Explorer cache location not verified' } else { 'On this PC' } }
            'Custom' { if ($shellClass -eq 'OneDrive') { 'Explorer cache still points at OneDrive' } elseif ($shellClass -eq 'Unknown') { 'Explorer cache location not verified' } else { 'On this PC (custom folder)' } }
            'OneDrive' { 'Still in OneDrive' }
            'Missing' { 'Not recorded' }
            default { 'Location not verified' }
        }
        if ($aliasClasses -contains 'OneDrive') { $status='Additional Windows location is in OneDrive' }
        elseif (@($aliasClasses | Where-Object { $_ -notin @('Local','Custom') }).Count) { $status='Additional Windows location not verified' }
        $note=''
        if ($cloud.Count -gt 0) { $note="$($cloud.Count) online-only file(s). Right-click the folder and choose Always keep on this device, then turn backup off again." }
        if ($cloud.Capped) { $note=($note+' Scan stopped after the file limit.').Trim() }
        elseif ($cloud.Incomplete) { $note=($note+' Scan incomplete: linked, virtual or inaccessible locations were not followed. A zero count does not prove files are downloaded.').Trim() }
        if ($aliasNotes.Count) { $note=($note+' '+($aliasNotes -join '; ')).Trim() }
        [void]$folders.Add([pscustomobject]@{
            Folder=$known.Folder; ValueName=$known.ValueName; Location=$location; Status=$status; Note=$note
            UserClass=$userClass; ShellClass=$shellClass; AliasClasses=$aliasClasses
        })
    }
    $redirected=@($folders | Where-Object { $_.UserClass -eq 'OneDrive' -or $_.ShellClass -eq 'OneDrive' -or $_.AliasClasses -contains 'OneDrive' })
    $uncertain=@($folders | Where-Object { $_.UserClass -in @('Missing','Unknown') -or $_.ShellClass -eq 'Unknown' -or @($_.AliasClasses | Where-Object { $_ -in @('Missing','Unknown') }).Count })
    $optOut=$false; $silent=$false; $wizard=$false; $locked=$false
    if (Test-Path -LiteralPath $PolicyKey) {
        $optOutState=Get-RegistryValueState -Path $PolicyKey -Name 'KFMBlockOptOut'
        $optOut=$optOutState.Exists -and $optOutState.Kind -in @('DWord','QWord') -and [int64]$optOutState.Value -eq 1
        $silentState=Get-RegistryValueState -Path $PolicyKey -Name 'KFMSilentOptIn'
        $silent=$silentState.Exists -and $silentState.Value -is [string] -and [bool]$silentState.Value.Trim()
        $wizardState=Get-RegistryValueState -Path $PolicyKey -Name 'KFMOptInWithWizard'
        $wizard=$wizardState.Exists -and $wizardState.Value -is [string] -and [bool]$wizardState.Value.Trim()
        $lockState=Get-RegistryValueState -Path $PolicyKey -Name 'KFMBlockOptIn'
        $locked=$lockState.Exists -and $lockState.Kind -in @('DWord','QWord') -and [int64]$lockState.Value -eq 1
    }
    $policyBlock=''
    if ($redirected.Count) { $policyBlock='Still pointing at OneDrive: '+((@($redirected.Folder) | Select-Object -Unique) -join ', ')+'. Before uninstalling, use OneDrive Settings > Sync and backup > Manage backup. Stop backup for each affected folder and choose Only on my PC. Download online-only files first if prompted. If OneDrive is already removed, open Recovery instructions. Nothing was changed.' }
    elseif ($uncertain.Count) { $policyBlock='Windows folder locations could not be verified: '+(@($uncertain.Folder) -join ', ')+'. Check for missing folders, invalid paths, unavailable drives or links. Nothing was changed.' }
    elseif ($optOut) { $policyBlock='Policy KFMBlockOptOut is forcing known folders to stay in OneDrive, so the backup toggles cannot move them back. Nothing was changed.' }
    elseif ($silent -or $wizard) { $policyBlock='Policy KFMSilentOptIn or KFMOptInWithWizard is set to move folders into OneDrive. Microsoft says the local lock does not apply while that policy is on. Nothing was changed.' }
    $policyAllowed=[string]::IsNullOrEmpty($policyBlock)
    $appInstalled=[bool]$OneDriveExecutable
    $uninstallAllowed=$policyAllowed -and $appInstalled
    $restoreAllowed=$false
    $uninstallBlock=$(if ($uninstallAllowed) { '' } elseif ($policyBlock) { $policyBlock } else { 'OneDrive is not installed, and the folders are already on this PC. No files were deleted.' })
    $restoreBlock='Automatic registry folder restore is retired. Use the recovery instructions to restore access through Windows and OneDrive. Original paths and files are preserved.'
    $summary=$(if ($policyBlock -and $redirected.Count) { $policyBlock }
        elseif ($policyBlock) { $policyBlock }
        elseif ($locked -and -not $appInstalled) { 'Folder locations are local. OneDrive is not installed; KFMBlockOptIn prevents future backup opt-in for Desktop, Documents and Pictures. No sign-in is needed.' }
        elseif ($locked) { 'Folders are on this PC and OneDrive is blocked from taking them. Uninstall Microsoft OneDrive from Installed apps only now. The toolkit does not delete files.' }
        elseif ($appInstalled) { 'Folder locations are local. No OneDrive sign-in is needed. You can lock Desktop, Documents and Pictures against future backup opt-in, then use Installed apps if you want to uninstall OneDrive. Check any other synced files separately.' }
        else { 'Folders are on this PC and OneDrive is not installed. Lock them so a later install cannot take Desktop, Documents and Pictures.' })
    # Windows PowerShell 5.1 rejects a pscustomobject cast when one property is an array of objects.
    $report=New-Object psobject
    $report | Add-Member NoteProperty Folders @($folders.ToArray())
    $report | Add-Member NoteProperty Summary $summary
    $report | Add-Member NoteProperty PolicyAllowed $policyAllowed
    $report | Add-Member NoteProperty PolicyBlock $policyBlock
    $report | Add-Member NoteProperty UninstallAllowed $uninstallAllowed
    $report | Add-Member NoteProperty UninstallBlock $uninstallBlock
    $report | Add-Member NoteProperty RestoreAllowed $restoreAllowed
    $report | Add-Member NoteProperty RestoreBlock $restoreBlock
    $report | Add-Member NoteProperty AppInstalled $appInstalled
    $report | Add-Member NoteProperty PolicyLocked $locked
    return $report
}
function Invoke-SuiteKnownFolderLock {
    param($Run,
        [string]$UserShellKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders',
        [string]$ShellKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
        [string]$PolicyKey='HKLM:\SOFTWARE\Policies\Microsoft\OneDrive',
        [string]$ProfilePath=$env:USERPROFILE,
        [string[]]$OneDriveRoots,
        [string]$OneDriveExecutable)
    $parameters=@{}
    foreach ($name in @('UserShellKey','ShellKey','PolicyKey','ProfilePath','OneDriveRoots','OneDriveExecutable')) {
        if ($PSBoundParameters.ContainsKey($name)) { $parameters[$name]=$PSBoundParameters[$name] }
    }
    $report=Get-SuiteOneDriveReport @parameters
    if (-not $report.PolicyAllowed) { throw $report.PolicyBlock }
    Set-SuiteRegistry -Run $Run -Path $PolicyKey -Name 'KFMBlockOptIn' -Value 1 -Kind 'DWord'
    return $report
}
function Invoke-SuiteOneDriveFolderRestore {
    param(
        [string]$UserShellKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders',
        [string]$ShellKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
        [string]$PolicyKey='HKLM:\SOFTWARE\Policies\Microsoft\OneDrive',
        [string]$ProfilePath=$env:USERPROFILE,
        [string[]]$OneDriveRoots,
        [string]$OneDriveExecutable)
    # Preserve an explicit refusal for older worker requests instead of a partial shell migration.
    throw 'Automatic registry folder restore is retired. Open the OneDrive recovery instructions; no paths or files were changed.'
}

Export-ModuleMember -Function *-Suite*
