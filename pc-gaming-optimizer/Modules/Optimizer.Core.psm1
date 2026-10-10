#requires -version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ToolkitVersion = '5.0.1'
$script:StateRoot = Join-Path $env:ProgramData 'WindowsPCToolkit\GamingOptimizer'
$script:SnapshotRoot = Join-Path $script:StateRoot 'Snapshots'
$script:LogRoot = Join-Path $script:StateRoot 'Logs'
$script:DiagnosticPath = Join-Path $env:LOCALAPPDATA 'WindowsPCToolkit\Logs\GamingOptimizer.log'
$script:DebugLog = $env:WINDOWS_PC_TOOLKIT_DEBUG -eq '1'

function Write-GamingDiagnostic {
    param([string]$Kind,[string]$Message)
    if (-not $script:DebugLog -and $Kind -notin @('FAIL','WARN')) { return }
    try {
        [void][IO.Directory]::CreateDirectory((Split-Path $script:DiagnosticPath -Parent))
        if ((Test-Path -LiteralPath $script:DiagnosticPath) -and (Get-Item -LiteralPath $script:DiagnosticPath).Length -gt 2MB) { Move-Item -LiteralPath $script:DiagnosticPath -Destination ($script:DiagnosticPath+'.1') -Force }
        [pscustomobject]@{Time=(Get-Date).ToString('o');Version=$script:ToolkitVersion;Kind=$Kind;Message=$Message} | ConvertTo-Json -Compress | Add-Content -LiteralPath $script:DiagnosticPath -Encoding UTF8
    } catch { Write-Warning ('Could not write gaming diagnostic log: '+$_.Exception.Message) }
}

function Initialize-GamingToolkit {
    foreach ($path in @($script:StateRoot, $script:SnapshotRoot, $script:LogRoot)) {
        if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }
    Write-GamingDiagnostic INFO ("Start; StateRoot=$script:StateRoot; SnapshotRoot=$script:SnapshotRoot; Debug=$script:DebugLog")
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    if (-not (Test-IsAdministrator)) { throw 'Administrator rights are required for this action.' }
}

function Write-ToolStatus {
    param([ValidateSet('OK','INFO','WARN','FAIL','STEP')][string]$Kind, [string]$Message)
    $color = switch ($Kind) { 'OK' {'Green'} 'INFO' {'Cyan'} 'WARN' {'Yellow'} 'FAIL' {'Red'} default {'White'} }
    $tag = switch ($Kind) { 'OK' {'[OK]'} 'INFO' {'[i]'} 'WARN' {'[!!]'} 'FAIL' {'[X]'} default {'[>>]'} }
    Write-Host ('  {0} {1}' -f $tag, $Message) -ForegroundColor $color
    Write-GamingDiagnostic $Kind $Message
}

function Write-GamingHeader {
    Clear-Host
    Write-Host '  ================================================================' -ForegroundColor DarkCyan
    Write-Host ('  PC GAMING OPTIMIZER  v{0}' -f $script:ToolkitVersion) -ForegroundColor Yellow
    Write-Host '  Measured settings, reversible changes, no registry folklore' -ForegroundColor Gray
    Write-Host '  ================================================================' -ForegroundColor DarkCyan
    Write-Host ''
}

function Get-RegistryValueState {
    param([string]$Path, [string]$Name)
    $exists = $false; $kind = $null; $value = $null
    if (Test-Path -LiteralPath $Path -ErrorAction Stop) {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if ($key.GetValueNames() -contains $Name) {
                $exists = $true
                $kind = $key.GetValueKind($Name).ToString()
                $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            }
    }
    [pscustomobject]@{ Path=$Path; Name=$Name; Exists=$exists; Kind=$kind; Value=$value }
}

function Set-RegistryValueExact {
    param([string]$Path, [string]$Name, [object]$Value, [string]$Kind='DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    $propertyType = switch ($Kind) {
        'String' {'String'} 'ExpandString' {'ExpandString'} 'Binary' {'Binary'}
        'DWord' {'DWord'} 'MultiString' {'MultiString'} 'QWord' {'QWord'} default {'String'}
    }
    $typedValue = switch ($propertyType) {
        'Binary' { ,([byte[]]@($Value)) }
        'DWord' { [int]$Value }
        'QWord' { [long]$Value }
        'MultiString' { ,([string[]]@($Value)) }
        default { $Value }
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $typedValue -PropertyType $propertyType -Force | Out-Null
    $actual=Get-RegistryValueState $Path $Name
    if (-not $actual.Exists -or $actual.Kind -ne $propertyType -or (ConvertTo-Json -InputObject $actual.Value -Compress) -cne (ConvertTo-Json -InputObject $typedValue -Compress)) { throw "Registry write verification failed: $Path\$Name" }
}

function Restore-RegistryValueState {
    param([pscustomobject]$State)
    if ($State.Exists) {
        Set-RegistryValueExact -Path $State.Path -Name $State.Name -Value $State.Value -Kind $State.Kind
    } else {
        if ((Get-RegistryValueState -Path $State.Path -Name $State.Name).Exists) { Remove-ItemProperty -LiteralPath $State.Path -Name $State.Name -ErrorAction Stop }
    }
}

function Get-ActivePowerSchemeGuid {
    try {
        $out = & "$env:SystemRoot\System32\powercfg.exe" /getactivescheme 2>$null
        if (($out -join ' ') -match '([0-9a-fA-F-]{36})') { return $matches[1] }
    } catch { }
    return $null
}


function Get-BcdOverrideStates {
    $names = @('useplatformclock','useplatformtick','disabledynamictick','tscsyncpolicy')
    $output = @(& "$env:SystemRoot\System32\bcdedit.exe" /enum '{current}' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Boot configuration could not be read (exit $LASTEXITCODE); no changes are safe." }
    foreach ($name in $names) {
        $line = $output | Where-Object { $_ -match ("^\s*{0}\s+(.+)$" -f [regex]::Escape($name)) } | Select-Object -First 1
        if ($line -and $line -match ("^\s*{0}\s+(.+)$" -f [regex]::Escape($name))) {
            [pscustomobject]@{ Name=$name; Exists=$true; Value=$matches[1].Trim() }
        } else { [pscustomobject]@{ Name=$name; Exists=$false; Value=$null } }
    }
}

function Get-NetworkAdapterStates {
    foreach ($adapter in Get-PhysicalNetAdapters) {
        $rss = Get-NetAdapterRss -Name $adapter.Name -ErrorAction SilentlyContinue
        $rsc = Get-NetAdapterRsc -Name $adapter.Name -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Name=$adapter.Name
            InterfaceGuid=$adapter.InterfaceGuid.ToString()
            InterfaceDescription=$adapter.InterfaceDescription
            RssAvailable=[bool]($null -ne $rss)
            RssEnabled=if($rss){[bool]$rss.Enabled}else{$false}
            RscAvailable=[bool]($null -ne $rsc)
            RscIPv4Enabled=if($rsc){[bool]$rsc.IPv4Enabled}else{$false}
            RscIPv6Enabled=if($rsc){[bool]$rsc.IPv6Enabled}else{$false}
        }
    }
}

function Get-GamingRegistryTargets {
    $targets = @(
        @{Path='HKCU:\Software\Microsoft\GameBar';Name='AllowAutoGameMode'},
        @{Path='HKCU:\Software\Microsoft\GameBar';Name='AutoGameModeEnabled'},
        @{Path='HKCU:\System\GameConfigStore';Name='GameDVR_Enabled'},
        @{Path='HKCU:\System\GameConfigStore';Name='GameDVR_FSEBehaviorMode'},
        @{Path='HKCU:\System\GameConfigStore';Name='GameDVR_HonorUserFSEBehaviorMode'},
        @{Path='HKCU:\System\GameConfigStore';Name='GameDVR_DXGIHonorFSEWindowsCompatible'},
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR';Name='AppCaptureEnabled'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers';Name='HwSchMode'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers';Name='HwSchMode2'},
        @{Path='HKCU:\Control Panel\Mouse';Name='MouseSpeed'},
        @{Path='HKCU:\Control Panel\Mouse';Name='MouseThreshold1'},
        @{Path='HKCU:\Control Panel\Mouse';Name='MouseThreshold2'},
        @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile';Name='NetworkThrottlingIndex'},
        @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile';Name='SystemResponsiveness'},
        @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games';Name='GPU Priority'},
        @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games';Name='Priority'},
        @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games';Name='Scheduling Category'},
        @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games';Name='SFIO Priority'},
        @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games';Name='Background Only'},
        @{Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games';Name='Clock Rate'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl';Name='Win32PrioritySeparation'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management';Name='LargeSystemCache'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem';Name='NtfsDisable8dot3NameCreation'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem';Name='NtfsDisableLastAccessUpdate'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem';Name='NtfsMemoryUsage'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem';Name='PathCache'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem';Name='NameCache'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling';Name='PowerThrottlingOff'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters';Name='MaxCacheTtl'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters';Name='MaxNegativeCacheTtl'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS';Name='Do not use NLA'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device';Name='IdlePowerMode'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\storahci\Parameters\Device';Name='NoLPM'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\storahci\Parameters\Device';Name='NoLPMDSTATE'},
        @{Path='HKLM:\SYSTEM\CurrentControlSet\Services\Disk';Name='TimeOutValue'}
    )
    $ifRoot='HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    if(Test-Path -LiteralPath $ifRoot){
        foreach($key in Get-ChildItem -LiteralPath $ifRoot -ErrorAction Stop){
            foreach($name in @('TcpAckFrequency','TCPNoDelay','TcpDelAckTicks')){$targets += @{Path=$key.PSPath;Name=$name}}
        }
    }
    $displayRoot='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    if(Test-Path -LiteralPath $displayRoot){
        foreach($key in Get-ChildItem -LiteralPath $displayRoot -ErrorAction Stop){
            foreach($name in @('PowerMizerEnable','PowerMizerLevel','PowerMizerLevelAC','PerLevelGPUCacheSize','ShaderCacheSize','MSISupported','MessageNumberLimit')){$targets += @{Path=$key.PSPath;Name=$name}}
        }
    }
    return $targets
}

function New-GamingSnapshot {
    param([string]$Reason='Manual change',[object[]]$RegistryTargets=(Get-GamingRegistryTargets),[switch]$IncludeServices,[switch]$IncludeBcd,[switch]$IncludeNetwork)
    Initialize-GamingToolkit
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $path = Join-Path $script:SnapshotRoot ("gaming_{0}.json" -f $stamp)
    $registry = foreach ($t in $RegistryTargets) { Get-RegistryValueState -Path $t.Path -Name $t.Name }
    $services = if ($IncludeServices) { foreach ($name in @('SysMain')) {
        $svc = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $name) -ErrorAction Stop
        if ($svc) { [pscustomobject]@{Name=$name; StartMode=$svc.StartMode; State=$svc.State} }
    } }
    $snapshot = [pscustomobject]@{
        Schema=3; ToolkitVersion=$script:ToolkitVersion; Created=(Get-Date).ToString('o'); Reason=$Reason
        Computer=$env:COMPUTERNAME; UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        PowerScheme=$null; Registry=@($registry | Where-Object { $null -ne $_ }); Services=@($services | Where-Object { $null -ne $_ })
        BcdOverrides=@(if($IncludeBcd){Get-BcdOverrideStates}); NetworkAdapters=@(if($IncludeNetwork){Get-NetworkAdapterStates})
    }
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $script:StateRoot 'latest_snapshot.txt') -Value $path -Encoding UTF8
    Write-ToolStatus OK ("Safety snapshot saved: {0}" -f $path)
    return $path
}

function Get-LatestGamingSnapshotPath {
    $pointer = Join-Path $script:StateRoot 'latest_snapshot.txt'
    if (Test-Path -LiteralPath $pointer) {
        $path = (Get-Content -LiteralPath $pointer -Raw).Trim()
        if ([IO.Path]::GetFullPath($path).StartsWith([IO.Path]::GetFullPath($script:SnapshotRoot).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
        Write-ToolStatus WARN 'Snapshot pointer is outside the local snapshot folder or missing; using the newest local snapshot instead.'
    }
    $latest = Get-ChildItem -LiteralPath $script:SnapshotRoot -Filter 'gaming_*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

function Restore-LatestGamingSnapshot {
    Assert-Administrator
    Initialize-GamingToolkit
    $path = Get-LatestGamingSnapshotPath
    if (-not $path) { Write-ToolStatus WARN 'No optimizer snapshot exists yet.'; return }
    $snap = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($snap.Schema -notin @(1,2,3)) { throw 'Unsupported gaming snapshot schema.' }
    if ($snap.Schema -eq 3 -and ($snap.Computer -ne $env:COMPUTERNAME -or $snap.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) { throw 'This gaming snapshot belongs to another computer or user.' }
    if ($snap.Schema -lt 3) { Write-ToolStatus WARN 'Legacy snapshot has no recorded computer/user identity and may include unrelated settings. Restore only your own local backup.' }
    $allowed=@(Get-GamingRegistryTargets)
    foreach ($state in @($snap.Registry)) {
        if (-not @($allowed | Where-Object { $_.Path -eq $state.Path -and $_.Name -eq $state.Name }).Count) { throw 'Gaming snapshot contains an unsupported registry target.' }
        if ($state.Exists -isnot [bool] -or ($state.Exists -and $state.Kind -notin @('String','ExpandString','Binary','DWord','MultiString','QWord'))) { throw 'Gaming snapshot contains an invalid registry state.' }
    }
    foreach ($svcState in @($snap.Services)) {
        if ($svcState.Name -ne 'SysMain' -or $svcState.StartMode -notin @('Auto','Manual','Disabled') -or $svcState.State -notin @('Running','Stopped')) { throw 'Gaming snapshot contains an unsupported service state.' }
    }
    if ($snap.PowerScheme -and $snap.PowerScheme -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { throw 'Gaming snapshot contains an invalid power scheme.' }
    if ($snap.PSObject.Properties.Name -contains 'BcdOverrides') {
        foreach ($state in @($snap.BcdOverrides)) { if ($state.Name -notin @('useplatformclock','useplatformtick','disabledynamictick','tscsyncpolicy') -or $state.Exists -isnot [bool]) { throw 'Gaming snapshot contains an unsupported boot state.' } }
    }
    Write-ToolStatus WARN 'Restoring a console snapshot can replace later manual changes. Review its path and scope before continuing.'
    if ((Read-Host ("  Restore snapshot '$path'? (y/N)")) -notmatch '^[Yy]$') { return }
    foreach ($state in @($snap.Registry)) {
        Restore-RegistryValueState -State $state
        $actual=Get-RegistryValueState $state.Path $state.Name
        if ($actual.Exists -ne $state.Exists -or ($actual.Exists -and ($actual.Kind -ne $state.Kind -or (ConvertTo-Json -InputObject $actual.Value -Compress) -cne (ConvertTo-Json -InputObject $state.Value -Compress)))) { throw "Registry restore verification failed: $($state.Path)\$($state.Name)" }
    }
    foreach ($svcState in @($snap.Services)) {
        $startType = switch ($svcState.StartMode) { 'Auto' {'Automatic'} 'Manual' {'Manual'} 'Disabled' {'Disabled'} default {$null} }
        if ($startType) { Set-Service -Name $svcState.Name -StartupType $startType -ErrorAction Stop }
        if ($svcState.State -eq 'Running') { Start-Service -Name $svcState.Name -ErrorAction Stop }
        elseif ($svcState.State -eq 'Stopped') { Stop-Service -Name $svcState.Name -Force -ErrorAction Stop }
        $actualService=Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $svcState.Name) -ErrorAction Stop
        if ($actualService.State -ne $svcState.State -or $actualService.StartMode -ne $svcState.StartMode) { throw "Service restore verification failed: $($svcState.Name)" }
    }
    if ($snap.PSObject.Properties.Name -contains 'NetworkAdapters') {
        foreach ($adapterState in @($snap.NetworkAdapters)) {
            $adapter = if ($adapterState.PSObject.Properties.Name -contains 'InterfaceGuid') { Get-NetAdapter -ErrorAction Stop | Where-Object { $_.InterfaceGuid.ToString() -eq $adapterState.InterfaceGuid } | Select-Object -First 1 } else { Get-NetAdapter -Name $adapterState.Name -ErrorAction Stop }
            if (-not $adapter) { throw "Original adapter not found: $($adapterState.Name)" }
            if ($adapterState.RssAvailable) {
                if ($adapterState.RssEnabled) { Enable-NetAdapterRss -Name $adapter.Name -Confirm:$false -ErrorAction Stop }
                else { Disable-NetAdapterRss -Name $adapter.Name -Confirm:$false -ErrorAction Stop }
                if ([bool](Get-NetAdapterRss -Name $adapter.Name -ErrorAction Stop).Enabled -ne [bool]$adapterState.RssEnabled) { throw "RSS restore verification failed: $($adapter.Name)" }
            }
            if ($adapterState.RscAvailable) {
                Set-NetAdapterRsc -Name $adapter.Name -IPv4Enabled ([bool]$adapterState.RscIPv4Enabled) -IPv6Enabled ([bool]$adapterState.RscIPv6Enabled) -NoRestart -ErrorAction Stop
                $rsc=Get-NetAdapterRsc -Name $adapter.Name -ErrorAction Stop
                if ([bool]$rsc.IPv4Enabled -ne [bool]$adapterState.RscIPv4Enabled -or [bool]$rsc.IPv6Enabled -ne [bool]$adapterState.RscIPv6Enabled) { throw "RSC restore verification failed: $($adapter.Name)" }
            }
        }
    }
    if ($snap.PSObject.Properties.Name -contains 'BcdOverrides') {
        foreach ($bcdState in @($snap.BcdOverrides)) {
            $current=Get-BcdOverrideStates | Where-Object Name -eq $bcdState.Name
            if (-not $current) { throw "Unknown BCD setting: $($bcdState.Name)" }
            if ($bcdState.Exists) { & "$env:SystemRoot\System32\bcdedit.exe" /set '{current}' $bcdState.Name $bcdState.Value 2>$null | Out-Null }
            elseif ($current.Exists) { & "$env:SystemRoot\System32\bcdedit.exe" /deletevalue '{current}' $bcdState.Name 2>$null | Out-Null }
            else { continue }
            if ($LASTEXITCODE -ne 0) { throw "BCD restore failed for $($bcdState.Name) (exit $LASTEXITCODE)." }
            $verified=Get-BcdOverrideStates | Where-Object Name -eq $bcdState.Name
            if ($verified.Exists -ne $bcdState.Exists -or ($verified.Exists -and $verified.Value -cne $bcdState.Value)) { throw "BCD restore verification failed: $($bcdState.Name)" }
        }
    }
    if ($snap.PowerScheme) {
        & "$env:SystemRoot\System32\powercfg.exe" /setactive $snap.PowerScheme | Out-Null
        if ($LASTEXITCODE -ne 0 -or (Get-ActivePowerSchemeGuid) -ne $snap.PowerScheme) { throw 'Power scheme restore verification failed.' }
    }
    Write-ToolStatus OK ("Restored exact state from {0}" -f $path)
    Write-ToolStatus INFO 'A sign-out or reboot may be needed for every setting to refresh.'
}

function Get-HagsState {
    try {
        $v = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction Stop).HwSchMode
        if ($v -eq 2) { return 'Enabled' }
        if ($v -eq 1) { return 'Disabled' }
        return "Configured ($v)"
    } catch { return 'Windows default / driver controlled' }
}

function Invoke-HagsManager {
    Assert-Administrator
    Write-Host ''
    Write-ToolStatus INFO ("Current HAGS state: {0}" -f (Get-HagsState))
    Write-Host '  [1] Enable HAGS   [2] Disable HAGS   [0] Leave unchanged'
    $choice = Read-Host '  Selection'
    if ($choice -notin @('1','2')) { Write-ToolStatus INFO 'No change made.'; return }
    New-GamingSnapshot -Reason 'HAGS change' -RegistryTargets @(@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers';Name='HwSchMode'}) | Out-Null
    $value = if ($choice -eq '1') { 2 } else { 1 }
    Set-RegistryValueExact -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value $value -Kind DWord
    Write-ToolStatus OK 'HAGS setting changed. Reboot required.'
    Write-ToolStatus INFO 'Benchmark both states. HAGS is not universally faster and can affect VR differently.'
}

function Invoke-SafeGamingProfile {
    param([switch]$DisableCaptures)
    Assert-Administrator
    $names=@('AllowAutoGameMode','AutoGameModeEnabled'); if($DisableCaptures){$names+=@('GameDVR_Enabled','AppCaptureEnabled')}
    New-GamingSnapshot -Reason 'Safe gaming profile' -RegistryTargets @(Get-GamingRegistryTargets | Where-Object { $_.Name -in $names }) | Out-Null
    Set-RegistryValueExact -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1 -Kind DWord
    Set-RegistryValueExact -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Kind DWord
    if ($DisableCaptures) {
        Set-RegistryValueExact -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Kind DWord
        Set-RegistryValueExact -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0 -Kind DWord
        Write-ToolStatus OK 'Background capture disabled. Xbox Game Bar itself was not removed.'
    }
    Write-ToolStatus OK 'Windows Game Mode enabled.'
    Write-ToolStatus INFO 'Power plan, SysMain, CPU scheduling, timer resolution, NIC offloads, and sleep settings were preserved.'
    Write-ToolStatus INFO ("HAGS was preserved: {0}" -f (Get-HagsState))
}

function Invoke-ShaderCacheCleanup {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'D3DSCache'),
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'),
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'),
        (Join-Path $env:LOCALAPPDATA 'AMD\DxCache'),
        (Join-Path $env:LOCALAPPDATA 'AMD\GLCache'),
        (Join-Path $env:LOCALAPPDATA 'Intel\ShaderCache')
    )
    $removed = 0; $skipped=0; $bytes = [int64]0
    $localRoot=[IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $ancestor=$path; $linked=$false
        while ($ancestor -and $ancestor.Length -ge $localRoot.Length) {
            if ((Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { $linked=$true; break }
            $ancestor=Split-Path $ancestor -Parent
        }
        if ($linked) { $skipped++; continue }
        $pending=New-Object 'Collections.Generic.Stack[string]'; $pending.Push($path)
        while ($pending.Count) {
            foreach ($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction Stop)) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $skipped++; continue }
                if ($item.PSIsContainer) { $pending.Push($item.FullName); continue }
                try { $length=$item.Length; Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop; $bytes+=$length; $removed++ } catch { $skipped++ }
            }
        }
    }
    Write-ToolStatus OK ("Removed {0} shader-cache files ({1:N1} MB)." -f $removed, ($bytes / 1MB))
    if ($skipped) { Write-ToolStatus WARN "$skipped linked or locked cache items skipped." }
    Write-ToolStatus INFO 'The first launch of each game may stutter while shaders rebuild. Use this for troubleshooting, not routine maintenance.'
}

function Show-GpuAudit {
    Write-Host ''
    Write-Host '  GPU / DRIVER AUDIT' -ForegroundColor Cyan
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    if (-not $gpus) { Write-ToolStatus WARN 'No GPU data returned by WMI.'; return }
    foreach ($gpu in $gpus) {
        Write-Host ("  GPU      : {0}" -f $gpu.Name)
        Write-Host ("  Driver   : {0}" -f $gpu.DriverVersion)
        if ($gpu.AdapterRAM) { Write-Host ("  VRAM WMI : {0:N1} GB (WMI can under-report modern cards)" -f ([double]$gpu.AdapterRAM / 1GB)) }
        Write-Host ''
    }
    if (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) {
        & nvidia-smi.exe --query-gpu=name,driver_version,memory.total,pstate,power.draw --format=csv,noheader 2>$null
    }
    Write-ToolStatus INFO 'No undocumented PowerMizer or shader-cache registry values were written.'
}

function Get-PhysicalNetAdapters {
    @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -ne 'Disabled' })
}

function Show-NetworkAudit {
    Write-Host ''
    Write-Host '  NETWORK AUDIT' -ForegroundColor Cyan
    try { Write-Host ('  TCP autotuning : ' + ((& "$env:SystemRoot\System32\netsh.exe" int tcp show global 2>$null) -join "`n")) } catch { }
    foreach ($a in Get-PhysicalNetAdapters) {
        $rss = Get-NetAdapterRss -Name $a.Name -ErrorAction SilentlyContinue
        $rsc = Get-NetAdapterRsc -Name $a.Name -ErrorAction SilentlyContinue
        $dnsState = Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $rssText = if($rss){$rss.Enabled}else{'N/A'}
        $rscText = if($rsc){$rsc.IPv4Enabled}else{'N/A'}
        $dns = if($dnsState){$dnsState.ServerAddresses -join ', '}else{'N/A'}
        Write-Host ("`n  {0} ({1})" -f $a.Name, $a.LinkSpeed) -ForegroundColor White
        Write-Host ("    RSS: {0}   RSC IPv4: {1}   DNS: {2}" -f $rssText, $rscText, $dns)
    }
    Write-ToolStatus INFO 'RSS, RSC, checksum offloads, interrupt moderation, and TCP autotuning are left at driver/Windows defaults unless measured evidence says otherwise.'
}

function Remove-RegistryValueIfPresent {
    param([string]$Path,[string]$Name)
    if (Test-Path -LiteralPath $Path) {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($key -and ($key.GetValueNames() -contains $Name)) {
            Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            if ((Get-RegistryValueState $Path $Name).Exists) { throw "Registry removal verification failed: $Path\$Name" }
            Write-ToolStatus OK ("Removed legacy override: {0}\{1}" -f $Path,$Name)
        }
    }
}

function Invoke-LegacyNetworkCleanup {
    Assert-Administrator
    Write-ToolStatus WARN 'This removes old suite latency tweaks, then returns core TCP settings to supported defaults. DNS is preserved.'
    $confirm = Read-Host '  Continue? (y/N)'
    if ($confirm -notmatch '^[Yy]$') { Write-ToolStatus INFO 'Cancelled.'; return }
    New-GamingSnapshot -Reason 'Legacy network tweak cleanup' -RegistryTargets @(Get-GamingRegistryTargets | Where-Object { $_.Name -in @('NetworkThrottlingIndex','SystemResponsiveness','TcpAckFrequency','TCPNoDelay','TcpDelAckTicks') }) -IncludeNetwork | Out-Null
    $sysProfile='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Remove-RegistryValueIfPresent $sysProfile 'NetworkThrottlingIndex'
    Remove-RegistryValueIfPresent $sysProfile 'SystemResponsiveness'
    $ifRoot='HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    if (Test-Path -LiteralPath $ifRoot) {
        foreach ($key in Get-ChildItem -LiteralPath $ifRoot -ErrorAction Stop) {
            foreach ($name in @('TcpAckFrequency','TCPNoDelay','TcpDelAckTicks')) { Remove-RegistryValueIfPresent $key.PSPath $name }
        }
    }
    Enable-GamingSupportedOffloads
    Write-ToolStatus OK 'Legacy Nagle/QoS/MMCSS overrides removed; supported RSS/RSC offloads enabled where available.'
    Write-ToolStatus INFO 'TCP autotuning was preserved rather than guessed.'
    Write-ToolStatus INFO 'Adapter DNS addresses and DoH entries were not touched.'
}

function Show-StorageAudit {
    Write-Host ''
    Write-Host '  STORAGE AUDIT' -ForegroundColor Cyan
    & "$env:SystemRoot\System32\fsutil.exe" behavior query DisableDeleteNotify 2>$null
    Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName,MediaType,HealthStatus,OperationalStatus,Size | Format-Table -AutoSize
    Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter | Select-Object DriveLetter,FileSystem,HealthStatus,SizeRemaining,Size | Format-Table -AutoSize
    Write-ToolStatus INFO '8.3 names, last-access timestamps, NTFS caches, disk timeouts, and storage power management were not modified.'
}

function Invoke-SafeRetrim {
    Assert-Administrator
    $physical=@(Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.MediaType -eq 'SSD' -and -not [string]::IsNullOrWhiteSpace($_.SerialNumber) })
    $count=0
    foreach ($disk in Get-Disk -ErrorAction Stop) {
        if ([string]::IsNullOrWhiteSpace($disk.SerialNumber)) { continue }
        $matches=@($physical | Where-Object { $_.SerialNumber.Trim() -eq $disk.SerialNumber.Trim() })
        if ($matches.Count -ne 1) { continue }
        foreach ($v in @(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop | Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -in @('NTFS','ReFS') })) {
            Optimize-Volume -DriveLetter $v.DriveLetter -ReTrim -Verbose -ErrorAction Stop
            $count++; Write-ToolStatus OK ("ReTrim completed on {0}:" -f $v.DriveLetter)
        }
    }
    Write-ToolStatus INFO "$count confirmed SSD volumes processed; HDD and unknown media preserved."
}

function Show-MemoryAudit {
    $os=Get-CimInstance Win32_OperatingSystem
    $total=[double]$os.TotalVisibleMemorySize*1KB
    $free=[double]$os.FreePhysicalMemory*1KB
    Write-Host ("  RAM used : {0:N1} GB / {1:N1} GB ({2:N0}%)" -f (($total-$free)/1GB),($total/1GB),(($total-$free)/$total*100))
    Get-Counter '\Memory\Available MBytes','\Memory\Cache Bytes','\Memory\Committed Bytes' -ErrorAction SilentlyContinue | ForEach-Object { $_.CounterSamples } | Select-Object Path,CookedValue | Format-Table -AutoSize
    Write-ToolStatus INFO 'Standby memory is a reusable file cache, not leaked RAM. This toolkit no longer purges it before games.'
}

function Show-TimerAudit {
    Write-Host ''
    Write-Host '  TIMER / BOOT CONFIG AUDIT' -ForegroundColor Cyan
    $interesting = @(Get-BcdOverrideStates | Where-Object Exists)
    if ($interesting) { $interesting | ForEach-Object { Write-Host ('  {0}: {1}' -f $_.Name,$_.Value) -ForegroundColor Yellow } }
    else { Write-ToolStatus OK 'No legacy timer overrides were found in the current boot entry.' }
    try {
        $timer = Get-CimInstance Win32_PerfFormattedData_PerfOS_System -ErrorAction Stop
        Write-Host ("  Context switches/sec: {0}" -f $timer.ContextSwitchesPersec)
    } catch { }
    Write-ToolStatus INFO 'Timer resolution is process-scoped on modern Windows. A permanent 0.5 ms request is not a universal FPS optimization.'
}

function Invoke-LegacyTimerCleanup {
    Assert-Administrator
    Write-ToolStatus WARN 'This deletes old BCD timer overrides and restores Windows automatic timer selection.'
    $confirm=Read-Host '  Continue? (y/N)'
    if ($confirm -notmatch '^[Yy]$') { return }
    New-GamingSnapshot -Reason 'Legacy timer override cleanup' -RegistryTargets @() -IncludeBcd | Out-Null
    Remove-GamingBcdOverrides
    Write-ToolStatus OK 'Legacy BCD timer overrides removed. Reboot required.'
}

function Show-GpuMsiAudit {
    Write-Host ''
    Write-Host '  GPU MSI MODE AUDIT (READ-ONLY)' -ForegroundColor Cyan
    $devices = @(Get-PnpDevice -Class Display -PresentOnly -ErrorAction SilentlyContinue)
    foreach ($d in $devices) {
        $instance = $d.InstanceId
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $instance + '\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties'
        $value = $null
        try { $value=(Get-ItemProperty -LiteralPath $path -Name MSISupported -ErrorAction Stop).MSISupported } catch { }
        $state = if ($value -eq 1) {'Enabled'} elseif ($value -eq 0) {'Disabled'} else {'Not exposed / driver default'}
        Write-Host ("  {0}: {1}" -f $d.FriendlyName,$state)
    }
    Write-ToolStatus INFO 'The old script wrote MSI values at an unsafe class-key level. v4.0 is read-only because changing interrupt mode can make a GPU unbootable.'
}

function Invoke-InputProfile {
    Assert-Administrator
    $choice=Read-Host '  Disable Windows mouse acceleration for 1:1 pointer movement? (y/N)'
    if ($choice -notmatch '^[Yy]$') { Write-ToolStatus INFO 'No change made.'; return }
    New-GamingSnapshot -Reason 'Mouse acceleration change' -RegistryTargets @(Get-GamingRegistryTargets | Where-Object { $_.Name -in @('MouseSpeed','MouseThreshold1','MouseThreshold2') }) | Out-Null
    Set-RegistryValueExact -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0' -Kind String
    Set-RegistryValueExact -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Kind String
    Set-RegistryValueExact -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Kind String
    & "$env:SystemRoot\System32\rundll32.exe" user32.dll,UpdatePerUserSystemParameters 1, True 2>$null
    Write-ToolStatus OK 'Mouse acceleration disabled. Many games already use raw input, so benchmark feel rather than assuming lower latency.'
}

function Show-DisplayAudit {
    Write-Host ''
    Write-Host '  DISPLAY AUDIT' -ForegroundColor Cyan
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host ("  Monitor instance: {0}" -f $_.InstanceName)
    }
    Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate,DriverVersion | Format-Table -AutoSize
    Write-ToolStatus INFO 'Confirm the maximum refresh rate under Settings > System > Display > Advanced display. The script does not force undocumented modes.'
}

function New-BenchmarkSnapshot {
    Initialize-GamingToolkit
    $os=Get-CimInstance Win32_OperatingSystem
    $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus=@(Get-CimInstance Win32_VideoController | ForEach-Object { [pscustomobject]@{Name=$_.Name;DriverVersion=$_.DriverVersion} })
    $net=@(Get-PhysicalNetAdapters | ForEach-Object { [pscustomobject]@{Name=$_.Name;LinkSpeed=$_.LinkSpeed;Driver=$_.DriverVersion} })
    $ping=$null
    try { $ping=(Test-Connection -ComputerName 1.1.1.1 -Count 4 -ErrorAction Stop | Measure-Object ResponseTime -Average).Average } catch { }
    $obj=[pscustomobject]@{
        Created=(Get-Date).ToString('o'); Computer=$env:COMPUTERNAME; OS=$os.Caption; Build=$os.BuildNumber
        CPU=$cpu.Name; TotalRAMGB=[math]::Round([double]$os.TotalVisibleMemorySize/1MB,1)
        FreeRAMGB=[math]::Round([double]$os.FreePhysicalMemory/1MB,1); GPU=$gpus; Network=$net
        PingToOneDotOneMs=$ping; HAGS=(Get-HagsState); PowerScheme=(Get-ActivePowerSchemeGuid)
    }
    $path=Join-Path $script:LogRoot ("benchmark_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $obj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    $obj | Format-List
    Write-ToolStatus OK ("Benchmark snapshot saved: {0}" -f $path)
}

function Enable-StayAwake {
    if (-not ('StayAwake.Native' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace StayAwake { public static class Native { [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags); } }
'@
    }
    # Windows PowerShell treats high-bit hexadecimal literals as signed Int32.
    if ([StayAwake.Native]::SetThreadExecutionState([uint32]2147483649) -eq 0) { throw 'Windows could not enable the temporary stay-awake request.' }
}
function Disable-StayAwake {
    if ('StayAwake.Native' -as [type]) {
        if ([StayAwake.Native]::SetThreadExecutionState([uint32]2147483648) -eq 0) { throw 'Windows could not release the temporary stay-awake request.' }
    }
}

function Invoke-GameBooster {
    $procs=@(Get-Process | Where-Object { $_.MainWindowTitle } | Sort-Object ProcessName)
    $procs | Select-Object Id,ProcessName,MainWindowTitle | Format-Table -AutoSize
    $idText=Read-Host '  Enter the game process ID, or 0 to cancel'
    $pidValue=0
    if (-not [int]::TryParse($idText,[ref]$pidValue) -or $pidValue -le 0) { return }
    $p=$null; $old=$null
    try {
        $p=Get-Process -Id $pidValue -ErrorAction Stop
        $old=$p.PriorityClass
        if ($old -notin @('High','RealTime')) { $p.PriorityClass='AboveNormal' }
        Enable-StayAwake
        Write-ToolStatus OK ("Session mode active for {0}. Priority is {1}; sleep is blocked." -f $p.ProcessName,$p.PriorityClass)
        Write-ToolStatus INFO 'Press Enter to end session mode. No RAM purge or global timer request is used.'
        Read-Host | Out-Null
    } catch { Write-ToolStatus FAIL $_.Exception.Message }
    finally {
        if ($p -and $null -ne $old) { try { if (-not $p.HasExited) { $p.PriorityClass=$old } } catch { Write-ToolStatus WARN 'The game priority could not be restored.' } }
        try { Disable-StayAwake } catch { Write-ToolStatus WARN ('Stay-awake release failed: '+$_.Exception.Message) }
    }
}

function Show-VrAudit {
    Write-Host ''
    Write-Host '  PCVR READINESS AUDIT' -ForegroundColor Cyan
    Write-Host ("  HAGS       : {0}" -f (Get-HagsState))
    $vbs='Unknown'
    try { $dg=Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard; $vbs=$dg.VirtualizationBasedSecurityStatus } catch { }
    Write-Host ("  VBS status : {0}" -f $vbs)
    Write-Host ("  Power plan : {0}" -f (Get-ActivePowerSchemeGuid))
    Show-TimerAudit
    Write-ToolStatus INFO 'For VR, test HAGS both ways, use a wired high-speed USB port or stable Wi-Fi path, and watch compositor frame timing. v4.0 does not force timers or MMCSS values.'
}

function Invoke-LegacyOptimizerRepair {
    Assert-Administrator
    Write-ToolStatus WARN 'This removes unsupported tweaks left by v3.x: MMCSS/network overrides, NTFS/cache overrides, storage LPM overrides, and BCD timer flags.'
    $confirm=Read-Host '  Create a snapshot and clean them? (y/N)'
    if ($confirm -notmatch '^[Yy]$') { return }
    $targets=@(Get-GamingRegistryTargets | Where-Object { $_.Name -notin @('AllowAutoGameMode','AutoGameModeEnabled','GameDVR_Enabled','AppCaptureEnabled','HwSchMode','MouseSpeed','MouseThreshold1','MouseThreshold2') })
    New-GamingSnapshot -Reason 'Repair v3.x legacy tweaks' -RegistryTargets $targets -IncludeServices -IncludeNetwork -IncludeBcd | Out-Null
    foreach($target in $targets){
        Remove-RegistryValueIfPresent $target.Path $target.Name
    }
    $games='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
    Set-RegistryValueExact $games 'GPU Priority' 8 DWord
    Set-RegistryValueExact $games 'Priority' 2 DWord
    Set-RegistryValueExact $games 'Scheduling Category' 'Medium' String
    Set-RegistryValueExact $games 'SFIO Priority' 'Normal' String
    Set-RegistryValueExact $games 'Background Only' 'True' String
    Remove-RegistryValueIfPresent $games 'Clock Rate'
    Enable-GamingSupportedOffloads
    if(Get-Service -Name SysMain -ErrorAction SilentlyContinue){Set-Service -Name SysMain -StartupType Automatic -ErrorAction Stop;Start-Service -Name SysMain -ErrorAction Stop}
    Remove-GamingBcdOverrides
    Write-ToolStatus OK 'Legacy optimizer overrides removed. DNS, GPU drivers, active power plan, and TCP autotuning were preserved.'
    Write-ToolStatus INFO 'Reboot recommended.'
}

function Enable-GamingSupportedOffloads {
    foreach ($adapter in Get-NetworkAdapterStates) {
        if ($adapter.RssAvailable) {
            Enable-NetAdapterRss -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            if (-not (Get-NetAdapterRss -Name $adapter.Name -ErrorAction Stop).Enabled) { throw "RSS enable verification failed: $($adapter.Name)" }
        }
        if ($adapter.RscAvailable) {
            Enable-NetAdapterRsc -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            $rsc=Get-NetAdapterRsc -Name $adapter.Name -ErrorAction Stop
            if (-not $rsc.IPv4Enabled -or -not $rsc.IPv6Enabled) { throw "RSC enable verification failed: $($adapter.Name)" }
        }
    }
}

function Remove-GamingBcdOverrides {
    foreach ($state in @(Get-BcdOverrideStates | Where-Object Exists)) {
        & "$env:SystemRoot\System32\bcdedit.exe" /deletevalue '{current}' $state.Name 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "BCD removal failed for $($state.Name) (exit $LASTEXITCODE)." }
    }
    if (@(Get-BcdOverrideStates | Where-Object Exists).Count) { throw 'BCD cleanup verification failed.' }
}

function Resolve-SuiteToolPath {
    param([string[]]$RelativeCandidates)
    $suiteRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    foreach ($relative in $RelativeCandidates) {
        $candidate = [IO.Path]::GetFullPath((Join-Path $suiteRoot $relative))
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Open-PrivacyGuard {
    $path = Resolve-SuiteToolPath -RelativeCandidates @(
        'Pc Privacy Guard\PC_Privacy.ps1',
        'pc-privacy-guard\PC_Privacy.ps1'
    )
    if ($path) { & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $path }
    else { Write-ToolStatus WARN 'PC Privacy Guard was not found beside this optimizer.' }
}

function Open-DnsManager {
    $path = Resolve-SuiteToolPath -RelativeCandidates @(
        'Pc Privacy Guard\Optional DNS\DNS_Manager.ps1',
        'dns-encrypted-doh\DNS_Manager.ps1'
    )
    if ($path) { & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $path }
    else { Write-ToolStatus WARN 'Encrypted DNS Manager was not found.' }
}

Export-ModuleMember -Function *
