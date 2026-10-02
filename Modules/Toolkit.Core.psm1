#requires -version 5.1
param([string]$DataRoot=(Join-Path $env:ProgramData 'WindowsPCToolkit\Suite'))
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:SuiteRoot=Split-Path $PSScriptRoot -Parent
$script:SuiteDataRoot=$DataRoot
$script:SuiteVersion='3.0.0'

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
function Initialize-SuiteState {
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
    foreach ($name in @('Runs','Requests','AppBackups')) { [void][IO.Directory]::CreateDirectory((Join-Path $script:SuiteDataRoot $name)) }
}
function Save-SuiteJson {
    param([string]$Path,[object]$Value)
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
    return ($First.Kind -eq $Second.Kind -and (ConvertTo-Json -InputObject $First.Value -Compress) -eq (ConvertTo-Json -InputObject $Second.Value -Compress))
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
    if ($Entry.Status -eq 'Restored') { return }
    $current=Get-RegistryValueState -Path $Entry.Before.Path -Name $Entry.Before.Name
    if (Test-SuiteRegistryEqual $current $Entry.Before) { $Entry.Status='Restored'; return }
    if (-not (Test-SuiteRegistryEqual $current $Entry.After)) { throw "Changed since optimization; kept your current value: $($Entry.Before.Path)\$($Entry.Before.Name)" }
    Restore-RegistryValueState $Entry.Before
    if (-not (Test-SuiteRegistryEqual (Get-RegistryValueState $Entry.Before.Path $Entry.Before.Name) $Entry.Before)) { throw 'Registry undo read-back failed.' }
    $Entry.Status='Restored'
}

function Get-SuiteActionCatalog {
    @(
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
    $names=@('Microsoft.Copilot','Clipchamp.Clipchamp','Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection','Microsoft.People','Microsoft.Todos','Microsoft.WindowsFeedbackHub','Microsoft.YourPhone','Microsoft.ZuneMusic','Microsoft.ZuneVideo','MicrosoftCorporationII.MicrosoftFamily')
    foreach ($app in Get-AppxPackage -ErrorAction Stop | Where-Object { $names -contains $_.Name -and -not $_.IsFramework -and -not $_.NonRemovable }) {
        [pscustomobject]@{Id=$app.PackageFullName;Name=$app.Name;Version=[string]$app.Version;Location=$app.InstallLocation;Detail='Optional consumer app. Removal affects this user and its app data; package reinstall is available.'}
    }
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
    param([string[]]$ActionIds)
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
        [pscustomobject]@{Action=$action.Name;Category=$action.Category;Details=$details;Changes=@($action.Targets).Count}
    }
}
function Add-SuiteStep {
    param($Run,[string]$Action,[string]$Status,[string]$Message)
    [void]$Run.Steps.Add([pscustomobject]@{Action=$Action;Status=$Status;Message=$Message;Time=(Get-Date).ToString('o')})
    $Run.Message=$Message
    Save-SuiteJson $Run.Path $Run
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
                        $entry.After=$actual; $entry.Status='Applied'; Save-SuiteJson $run.Path $run
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
                        foreach ($item in Get-SuiteStartupItems | Where-Object { $_.Kind -eq 'Startup' -and $_.Missing }) { Set-SuiteRegistry $run $item.Path $item.ValueName $null -Remove; $count++ }
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
                    $task=Get-ScheduledTask -TaskPath $item.Path -TaskName $item.ValueName -ErrorAction Stop
                    $entry=[pscustomobject]@{Path=$item.Path;Name=$item.ValueName;Enabled=[bool]$task.Settings.Enabled;Status='Pending'}
                    [void]$run.Tasks.Add($entry); Save-SuiteJson $run.Path $run
                    Disable-ScheduledTask -TaskPath $item.Path -TaskName $item.ValueName -ErrorAction Stop | Out-Null
                    if ((Get-ScheduledTask -TaskPath $item.Path -TaskName $item.ValueName -ErrorAction Stop).Settings.Enabled) { throw 'Task disable verification failed.' }
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
                if ($source.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Package folder is a link; kept the app.' }
                if (@(Get-ChildItem -LiteralPath $source.FullName -Recurse -Force -ErrorAction Stop | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Package contains linked files/folders; kept the app.' }
                $backup=Join-Path $script:SuiteDataRoot ('AppBackups\'+$run.Id+'\'+$app.Id)
                [void][IO.Directory]::CreateDirectory($backup)
                # robocopy preserves long package paths and skips junctions. Codes 0-7 are success.
                $null=Invoke-SuiteNative "$env:SystemRoot\System32\robocopy.exe" @($app.Location,$backup,'/E','/XJ','/R:0','/W:0','/NFL','/NDL','/NJH','/NJS') @(0,1,2,3,4,5,6,7)
                if (-not (Test-Path -LiteralPath (Join-Path $backup 'AppxManifest.xml'))) { throw 'Package backup is incomplete; kept the app.' }
                foreach ($file in Get-ChildItem -LiteralPath $source.FullName -Recurse -File -Force -ErrorAction Stop) {
                    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'A package file is a link; kept the app.' }
                    $relative=$file.FullName.Substring($source.FullName.TrimEnd('\').Length).TrimStart('\')
                    $copy=Join-Path $backup $relative
                    if (-not (Test-Path -LiteralPath $copy) -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash) { throw 'Package backup verification failed; kept the app.' }
                }
                $entry=[pscustomobject]@{Name=$app.Name;Package=$app.Id;Backup=$backup;Status='Pending'}
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
    foreach ($file in Get-ChildItem -LiteralPath $directory -Filter '*.json' -File | Sort-Object Name -Descending) {
        try { $run=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; if ($run.UserSid -eq (Get-SuiteIdentity)) { $run } } catch { Write-Warning "Unreadable report: $($file.Name)" }
    }
}
function Invoke-SuiteUndo {
    param([string]$Path)
    Assert-Administrator
    $full=[IO.Path]::GetFullPath($Path)
    $root=[IO.Path]::GetFullPath((Join-Path $script:SuiteDataRoot 'Runs')).TrimEnd('\')+'\'
    if (-not $full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($full) -ne '.json') { throw 'Select a report from this toolkit history.' }
    $run=Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($run.Schema -ne 1 -or $run.Computer -ne $env:COMPUTERNAME -or $run.UserSid -ne (Get-SuiteIdentity)) { throw 'This backup belongs to another computer/user or uses an unsupported schema.' }
    if ($run.Status -eq 'Restored') { $run.Message='This operation was already restored. Current settings have been preserved.'; return $run }
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
                $task=Get-ScheduledTask -TaskPath $entry.Path -TaskName $entry.Name -ErrorAction Stop
                if ($entry.Enabled -and -not $task.Settings.Enabled) { Enable-ScheduledTask -TaskPath $entry.Path -TaskName $entry.Name -ErrorAction Stop | Out-Null }
                if ([bool](Get-ScheduledTask -TaskPath $entry.Path -TaskName $entry.Name -ErrorAction Stop).Settings.Enabled -ne [bool]$entry.Enabled) { throw 'Task was changed after optimization; current state preserved.' }
                $entry.Status='Restored'
            } catch { [void]$errors.Add($_.Exception.Message) }
            Save-SuiteJson $full $run
        }
        foreach ($entry in @($run.Apps)) {
            try {
                if ($entry.Status -eq 'Restored') { continue }
                if (-not (Get-AppxPackage -Name $entry.Name -ErrorAction Stop)) {
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
                    if ($current -ne $entry.After) { throw 'Windows feature changed since optimization; current state preserved.' }
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
            @{Name='DISM component-store repair';File='dism.exe';Args=@('/Online','/Cleanup-Image','/RestoreHealth')},
            @{Name='SFC system-file scan';File='sfc.exe';Args=@('/scannow')})) {
            $run.Message='Running: '+$step.Name; Save-SuiteJson $run.Path $run
            if ($Progress) { & $Progress $run }
            try {
                $native=Invoke-SuiteNative (Join-Path "$env:SystemRoot\System32" $step.File) $step.Args @(0,3010)
                Add-SuiteStep $run $step.Name 'Completed' ($native.Output+$(if ($native.RestartRequired) { ' Restart required.' } else { '' }))
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

Export-ModuleMember -Function *-Suite*
