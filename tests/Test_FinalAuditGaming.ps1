#requires -version 5.1
param([string]$Root=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
$checks=0
function Check([bool]$Condition,[string]$Message) { if(-not $Condition){throw "TEST FAILED: $Message"}; $script:checks++ }
$source=Join-Path $Root 'pc-gaming-optimizer\Modules\Optimizer.Core.psm1'
if(-not(Test-Path -LiteralPath $source)){$source=Join-Path $Root 'Pc Gaming Optimizer\Modules\Optimizer.Core.psm1'}
$fixture=Join-Path $env:TEMP ('Toolkit final gaming '+[guid]::NewGuid().ToString('N'))
$key='HKCU:\Software\WindowsPCToolkitTests\'+[guid]::NewGuid().ToString('N')
[void][IO.Directory]::CreateDirectory($fixture)
try {
    $module=Import-Module $source -Force -DisableNameChecking -PassThru
    & $module {
        param($fixture,$key)
        $script:StateRoot=Join-Path $fixture 'State';$script:SnapshotRoot=Join-Path $script:StateRoot 'Snapshots';$script:LogRoot=Join-Path $script:StateRoot 'Logs'
        $script:DiagnosticPath=Join-Path $fixture 'Gaming.log';$script:FixtureKey=$key
        function script:Assert-Administrator {}
        function script:Get-GamingRegistryTargets { @(@{Path=$script:FixtureKey;Name='First'},@{Path=$script:FixtureKey;Name='Second'}) }
        function script:Read-Host {'y'}
        function script:Get-NetAdapter { @() }
    } $fixture $key
    Set-RegistryValueExact $key First original String
    Set-RegistryValueExact $key Second 1 DWord
    $path=New-GamingSnapshot -RegistryTargets @(@{Path=$key;Name='First'},@{Path=$key;Name='Second'})
    $baseline=Get-Content -LiteralPath $path -Raw
    foreach($case in @('BadValue','MissingAdapter','BadNetworkType','DuplicateRegistry','BadBcd','BadKind','AbsentMalformed','BadSchema','BadCollection')) {
        $snapshot=$baseline|ConvertFrom-Json
        switch($case) {
            BadValue {$snapshot.Registry[1].Value='not an integer'}
            MissingAdapter {$snapshot.NetworkAdapters=@([pscustomobject]@{Name='Removed fixture';InterfaceGuid=[guid]::NewGuid().ToString();RssAvailable=$false;RssEnabled=$false;RscAvailable=$false;RscIPv4Enabled=$false;RscIPv6Enabled=$false})}
            BadNetworkType {$snapshot.NetworkAdapters=@([pscustomobject]@{Name='Fixture';InterfaceGuid=[guid]::NewGuid().ToString();RssAvailable='false';RssEnabled=$false;RscAvailable=$false;RscIPv4Enabled=$false;RscIPv6Enabled=$false})}
            DuplicateRegistry {$snapshot.Registry=@($snapshot.Registry[0],$snapshot.Registry[0])}
            BadBcd {$snapshot.BcdOverrides=@([pscustomobject]@{Name='tscsyncpolicy';Exists=$true;Value='invalid'})}
            BadKind {$snapshot.Registry[1].Kind=@('DWord','String')}
            AbsentMalformed {$snapshot.Registry[1].Exists=$false;$snapshot.Registry[1].Value='not an integer'}
            BadSchema {$snapshot.Schema='3'}
            BadCollection {$snapshot.Registry=$snapshot.Registry[0]}
        }
        $snapshot|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
        Set-RegistryValueExact $key First newer String
        $blocked=$false;try{Restore-LatestGamingSnapshot}catch{$blocked=$true}
        Check $blocked "$case snapshot is rejected"
        Check ((Get-RegistryValueState $key First).Value -ceq 'newer') "$case is rejected before the first registry write"
    }
    $baseline|Set-Content -LiteralPath $path -Encoding UTF8
    Restore-LatestGamingSnapshot
    Check ((Get-RegistryValueState $key First).Value -ceq 'original') 'Valid snapshot still restores typed registry values'
    & $module {
        $script:FixtureService=[pscustomobject]@{Name='SysMain';StartMode='Manual';State='Stopped'}
        function script:Get-CimInstance {$script:FixtureService}
        function script:Set-Service {param($Name,$StartupType) $script:FixtureService.StartMode=if($StartupType -eq 'Automatic'){'Auto'}else{$StartupType}}
        function script:Start-Service {if($script:FixtureService.StartMode -eq 'Disabled'){throw 'SCM 1058 fixture'};$script:FixtureService.State='Running'}
        function script:Stop-Service {$script:FixtureService.State='Stopped'}
    }
    $snapshot=$baseline|ConvertFrom-Json
    $snapshot.Services=@([pscustomobject]@{Name='SysMain';StartMode='Disabled';State='Running'})
    $snapshot|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
    Restore-LatestGamingSnapshot
    $service=& $module {$script:FixtureService}
    Check ($service.StartMode -eq 'Disabled' -and $service.State -eq 'Running') 'Disabled-but-running service state restores without SCM 1058'
    & $module {function script:Start-Service {throw 'Injected start failure'};$script:FixtureService.State='Stopped'}
    $blocked=$false;try{Restore-LatestGamingSnapshot}catch{$blocked=$_.Exception.Message -eq 'Injected start failure'}
    Check $blocked 'Failed service start remains a failed restore'
    $service=& $module {$script:FixtureService}
    Check ($service.StartMode -eq 'Disabled') 'Failed start restores Disabled instead of leaving temporary Manual mode'

    # Real linked state directories must fail before writing through their targets.
    $linked=Join-Path $fixture 'LinkedState';$outside=Join-Path $fixture 'Outside'
    [void][IO.Directory]::CreateDirectory($outside)
    New-Item -ItemType Junction -Path $linked -Target $outside|Out-Null
    try {
        & $module {param($linked) $script:StateRoot=$linked;$script:SnapshotRoot=Join-Path $linked 'Snapshots';$script:LogRoot=Join-Path $linked 'Logs'} $linked
        $blocked=$false;try{New-GamingSnapshot -RegistryTargets @()|Out-Null}catch{$blocked=$true}
        Check $blocked 'Linked gaming state root is rejected'
        Check (@(Get-ChildItem -LiteralPath $outside -Force).Count -eq 0) 'Linked state target remains untouched'
    } finally {[IO.Directory]::Delete($linked)}
    # A real HKCU fixture runs the actual snapshot-then-delete order: the Games block is
    # journaled, never deleted or rewritten, while the other legacy targets are removed.
    $gamesKey=Join-Path $key 'Tasks\Games'
    $legacyKey=Join-Path $key 'Legacy'
    New-Item -Path $gamesKey -Force|Out-Null
    New-Item -Path $legacyKey -Force|Out-Null
    Set-RegistryValueExact $gamesKey 'GPU Priority' 8 DWord
    Set-RegistryValueExact $gamesKey 'Priority' 5 DWord
    Set-RegistryValueExact $gamesKey 'Scheduling Category' 'High' String
    Set-RegistryValueExact $gamesKey 'Background Only' 'False' String
    Set-RegistryValueExact $gamesKey 'Clock Rate' 20000 DWord
    Set-RegistryValueExact $legacyKey 'NtfsMemoryUsage' 2 DWord
    Set-RegistryValueExact $legacyKey 'NetworkThrottlingIndex' 0 DWord
    & $module {
        param($gamesKey,$legacyKey)
        $script:GamingGamesTaskPath=$gamesKey
        $script:StateRoot=Join-Path $env:TEMP ('Gaming repair '+[guid]::NewGuid().ToString('N'))
        $script:SnapshotRoot=Join-Path $script:StateRoot 'Snapshots'
        function script:Get-GamingRegistryTargets {
            @(@{Path=$gamesKey;Name='GPU Priority'},@{Path=$gamesKey;Name='Priority'},@{Path=$gamesKey;Name='Scheduling Category'},@{Path=$gamesKey;Name='SFIO Priority'},@{Path=$gamesKey;Name='Background Only'},@{Path=$gamesKey;Name='Clock Rate'},@{Path=$legacyKey;Name='NtfsMemoryUsage'},@{Path=$legacyKey;Name='NetworkThrottlingIndex'})
        }
        function script:Get-CimInstance { param($ClassName,$Filter) [pscustomobject]@{StartMode='Auto';State='Running'} }
        function script:Get-BcdOverrideStates { @() }
        function script:Get-NetworkAdapterStates { @() }
        # The earlier service test leaves throwing stubs behind; restoring this journal needs no-ops.
        function script:Set-Service { param($Name,$StartupType) }
        function script:Start-Service { param($Name) }
        $script:RemoveCount=0
        $script:RealRemove=(Get-Command Remove-RegistryValueIfPresent -CommandType Function).ScriptBlock
    } $gamesKey $legacyKey
    Invoke-LegacyOptimizerRepair
    Check ((Get-RegistryValueState $gamesKey 'Priority').Value -eq 5) 'A custom MMCSS value survives the repair'
    Check ((Get-RegistryValueState $gamesKey 'Scheduling Category').Value -ceq 'High') 'A non-default scheduling category survives the repair'
    Check ((Get-RegistryValueState $gamesKey 'Background Only').Value -ceq 'False') 'A non-default background flag survives the repair'
    Check ((Get-RegistryValueState $gamesKey 'Clock Rate').Value -eq 20000) 'Clock Rate survives the repair'
    Check (-not (Get-RegistryValueState $gamesKey 'SFIO Priority').Exists) 'A missing MMCSS value stays missing instead of being invented'
    Check (-not (Get-RegistryValueState $legacyKey 'NtfsMemoryUsage').Exists -and -not (Get-RegistryValueState $legacyKey 'NetworkThrottlingIndex').Exists) 'Other legacy overrides are still removed'
    $journal=& $module { Get-Content -LiteralPath (Get-LatestGamingSnapshotPath) -Raw | ConvertFrom-Json }
    $journalGames=@($journal.Registry | Where-Object { $_.Path -eq $gamesKey })
    Check ($journalGames.Count -eq 6 -and (@($journalGames | Where-Object { $_.Name -eq 'Clock Rate' -and $_.Value -eq 20000 }).Count -eq 1)) 'All six Games values are journaled before the cleanup'

    # A failure halfway through removal leaves the journal usable: restoring it returns the value.
    Set-RegistryValueExact $legacyKey 'NtfsMemoryUsage' 2 DWord
    Set-RegistryValueExact $legacyKey 'NetworkThrottlingIndex' 0 DWord
    & $module { function script:Remove-RegistryValueIfPresent { param($Path,$Name) $script:RemoveCount++; if($script:RemoveCount -eq 2){throw 'Injected mid-operation failure'}; & $script:RealRemove $Path $Name } }
    $midFailed=$false; try { Invoke-LegacyOptimizerRepair } catch { $midFailed=$_.Exception.Message -eq 'Injected mid-operation failure' }
    Check $midFailed 'A mid-operation failure aborts the repair'
    Restore-LatestGamingSnapshot
    Check ((Get-RegistryValueState $legacyKey 'NtfsMemoryUsage').Value -eq 2 -and (Get-RegistryValueState $legacyKey 'NetworkThrottlingIndex').Value -eq 0) 'The recorded journal restores values removed before the failure'

    # No journal, no mutation.
    Set-RegistryValueExact $legacyKey 'NtfsMemoryUsage' 2 DWord
    & $module { function script:New-GamingSnapshot { throw 'Injected snapshot failure' } }
    $snapFailed=$false; try { Invoke-LegacyOptimizerRepair } catch { $snapFailed=$_.Exception.Message -eq 'Injected snapshot failure' }
    Check $snapFailed 'A failed snapshot aborts the repair'
    Check ((Get-RegistryValueState $legacyKey 'NtfsMemoryUsage').Value -eq 2) 'A failed snapshot removes nothing'
    Write-Host "PASS: $checks final gaming audit checks. Only disposable HKCU/files and intercepted adapters were used." -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Module Optimizer.Core -Force -ErrorAction SilentlyContinue
    if(-not [IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup escaped TEMP.'}
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
