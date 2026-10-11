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
    Write-Host "PASS: $checks final gaming audit checks. Only disposable HKCU/files and intercepted adapters were used." -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Module Optimizer.Core -Force -ErrorAction SilentlyContinue
    if(-not [IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture cleanup escaped TEMP.'}
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
