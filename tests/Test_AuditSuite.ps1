#requires -version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('ToolkitAudit_'+[guid]::NewGuid().ToString('N'))
$key='HKCU:\Software\WindowsPCToolkitTests\'+[guid]::NewGuid().ToString('N')
$checks=0
function Check([bool]$condition,[string]$message) { if (-not $condition) { throw "FAIL: $message" }; $script:checks++ }
function Fails([scriptblock]$body,[string]$message) { $failed=$false; try { & $body } catch { $failed=$true }; Check $failed $message }
[void][IO.Directory]::CreateDirectory($fixture)
try {
    Import-Module (Join-Path $root 'Modules\Toolkit.Core.psm1') -ArgumentList (Join-Path $fixture 'State') -Force -DisableNameChecking
    $module=Get-Module Toolkit.Core
    & $module { function script:Assert-Administrator {} }
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -LiteralPath $key -Name Text -Value Original -PropertyType String | Out-Null
    $run=New-SuiteRun 'CaseTest'
    Set-SuiteRegistry $run $key Text original String
    Check ($run.Registry.Count -eq 1 -and (Get-ItemPropertyValue $key Text) -ceq 'original') 'Case-only change is applied and journaled'
    Set-ItemProperty -LiteralPath $key -Name Text -Value ORIGINAL
    Fails { Undo-SuiteRegistryEntry $run.Registry[0] } 'Case-only intervening user change is preserved'
    Check ((Get-ItemPropertyValue $key Text) -ceq 'ORIGINAL') 'User string casing survives undo conflict'
    $run=New-SuiteRun 'Repair'
    Fails { Invoke-SuiteUndo $run.Path } 'Repair/empty journals cannot claim successful undo'
    $run.Path='C:\untrusted-report-path.json'; Save-SuiteJson (Join-Path (Get-SuiteDataRoot) ('Runs\'+$run.Id+'.json')) $run
    $history=@(Get-SuiteHistory)
    Check (@($history | Where-Object { $_.Path -eq 'C:\untrusted-report-path.json' }).Count -eq 0) 'History uses actual file path rather than a report-supplied path'
    $run.Computer='OtherComputer'; Save-SuiteJson (Join-Path (Get-SuiteDataRoot) ('Runs\'+$run.Id+'.json')) $run
    Check (@(Get-SuiteHistory | Where-Object Id -eq $run.Id).Count -eq 0) 'Foreign computer reports are excluded'
    $preview=& $module {
        try {
            function script:Get-SuiteStartupItems { [pscustomobject]@{Id='startup';Name='Fixture Startup';Target='fixture.exe'} }
            function script:Get-SuiteAppCatalog { [pscustomobject]@{Id='app';Name='Fixture App'} }
            @(Get-SuitePreview -ActionIds @() -StartupIds startup -AppIds app)
        } finally { Remove-Item Function:script:Get-SuiteStartupItems,Function:script:Get-SuiteAppCatalog }
    }
    Check ($preview.Count -eq 2 -and $preview[0].Category -eq 'Reviewed startup' -and $preview[1].Category -eq 'Reviewed apps') 'Preview covers reviewed-only selections'
    $literalTask=& $module {
        try {
            function script:Get-ScheduledTask { @([pscustomobject]@{TaskName='[literal]';TaskPath='\Fixture\'},[pscustomobject]@{TaskName='l';TaskPath='\Fixture\'}) }
            (Get-SuiteTask '\Fixture\' '[literal]').TaskName
        } finally { Remove-Item Function:script:Get-ScheduledTask }
    }
    Check ($literalTask -eq '[literal]') 'Task selection rejects wildcard expansion to other tasks'
    Check ((Get-Command Disable-ScheduledTask).Parameters.ContainsKey('InputObject') -and (Get-Command Enable-ScheduledTask).Parameters.ContainsKey('InputObject')) 'Real task mutation API supports exact task objects'
    Set-ItemProperty -LiteralPath $key -Name Text -Value ('"'+$env:SystemRoot+'\System32\cmd.exe"')
    $preserved=& $module {
        param($key)
        try {
            $script:FixtureKey=$key
            function script:Get-SuiteStartupItems { [pscustomobject]@{Kind='Startup';Missing=$true;Path=$script:FixtureKey;ValueName='Text'} }
            function script:Get-RegistryIssues { }
            $run=Invoke-SuiteRun -ActionIds RegistryCare -AppIds @()
            $run.Registry.Count -eq 0
        } finally { Remove-Item Function:script:Get-SuiteStartupItems,Function:script:Get-RegistryIssues }
    } $key
    Check $preserved 'Shared registry care preserves a valid startup replacement after a stale missing-target scan'
    $workerAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Toolkit.Worker.ps1'),[ref]$null,[ref]$null)
    $switch=$workerAst.Find({param($n) $n -is [Management.Automation.Language.SwitchStatementAst]},$true)
    $restore=[scriptblock]::Create(($switch.Clauses | Where-Object { $_.Item1.Value -eq 'RestorePoint' }).Item2.Extent.Text.TrimStart('{').TrimEnd('}'))
    & {
        param($body)
        function Get-ComputerRestorePoint { [pscustomobject]@{SequenceNumber=1;Description='Windows PC Toolkit'} }
        function Checkpoint-Computer { }
        Fails { & $body } 'No-output restore-point command cannot claim a point was created'
        $script:created=$false
        function Checkpoint-Computer { $script:created=$true }
        function Get-ComputerRestorePoint { [pscustomobject]@{SequenceNumber=$(if ($script:created) { 2 } else { 1 });Description='Windows PC Toolkit'} }
        & $body
        Check $script:created 'Restore-point success requires a new native sequence number'
    } $restore
    # Exercise the actual worker process for malformed requests and missing imports.
    $request=Join-Path $fixture 'broken.json'; [IO.File]::WriteAllText($request,'invalid json')
    Fails { Invoke-SuiteNative "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-File',(Join-Path $root 'Toolkit.Worker.ps1'),'-RequestPath',$request) } 'Malformed worker request exits unsuccessfully'
    $result=Get-Content -LiteralPath ($request+'.result.json') -Raw | ConvertFrom-Json
    Check ($result.Status -eq 'Failed' -and $result.Message) 'Malformed request produces visible failure result'
    Copy-Item -LiteralPath (Join-Path $root 'Toolkit.Worker.ps1') -Destination $fixture
    Fails { Invoke-SuiteNative "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-File',(Join-Path $fixture 'Toolkit.Worker.ps1'),'-RequestPath',$request) } 'Missing shared module exits unsuccessfully'
    $result=Get-Content -LiteralPath ($request+'.result.json') -Raw | ConvertFrom-Json
    Check ($result.Status -eq 'Failed' -and $result.Message -match 'Toolkit.Core') 'Missing module still produces failure result'
    $outside=Join-Path $fixture 'outside'; [void][IO.Directory]::CreateDirectory($outside)
    $link=Join-Path (Get-SuiteDataRoot) 'Requests'
    [IO.Directory]::Delete($link)
    & "$env:SystemRoot\System32\cmd.exe" /d /c "mklink /J `"$link`" `"$outside`"" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create owned junction fixture.' }
    Check (-not (Test-SuiteMissingExecutable (Join-Path $link 'missing.exe'))) 'Linked executable locations cannot be classified as confirmed missing'
    Fails { Initialize-SuiteState } 'Existing linked state folders are rejected before writes'
    Check (@(Get-ChildItem -LiteralPath $outside).Count -eq 0) 'Linked destination remains untouched'
    [IO.Directory]::Delete($link); $link=$null
    $savedLocal=$env:LOCALAPPDATA; $savedDebug=$env:WINDOWS_PC_TOOLKIT_DEBUG
    try {
        $env:LOCALAPPDATA=Join-Path $fixture 'DiagnosticLocal'; $env:WINDOWS_PC_TOOLKIT_DEBUG=$null
        Write-SuiteDiagnostic 'Quiet fixture' 'not logged'
        $diagnostic=Join-Path $env:LOCALAPPDATA 'WindowsPCToolkit\Logs\Suite.log'
        Check (-not (Test-Path -LiteralPath $diagnostic)) 'Default debug logging is quiet'
        Write-SuiteDiagnostic 'Failure fixture' ('x'*6000) 'Error'
        $line=Get-Content -LiteralPath $diagnostic -Raw | ConvertFrom-Json
        Check ($line.Message.Length -eq 4096 -and $line.Version -eq '3.0.1') 'Failure causes are bounded and versioned with debug off'
        $env:WINDOWS_PC_TOOLKIT_DEBUG='1'
        Write-SuiteDiagnostic 'Startup fixture' 'DataRoot=fixture; Debug=True'
        Check (@(Get-Content -LiteralPath $diagnostic).Count -eq 2) 'Explicit debug logging records state'
    } finally { $env:LOCALAPPDATA=$savedLocal; $env:WINDOWS_PC_TOOLKIT_DEBUG=$savedDebug }
    . (Join-Path $root 'Toolkit.ps1') -SmokeTest | Out-Null
    foreach ($check in $script:optionChecks.Values) { $check.IsChecked=$false }
    $script:controls.IncludeReviewed.IsChecked=$true
    $script:controls.StartupGrid.ItemsSource=@([pscustomobject]@{Id='fixture';Name='Reviewed startup'})
    $script:controls.StartupGrid.SelectedIndex=0
    $script:captured=$null
    function Start-ToolkitOperation { param($Operation,$Ids) $script:captured=$Operation }
    Invoke-ToolkitButton $script:controls.OptimizeButton $null
    Check ($script:captured -eq 'Optimize') 'Actual Optimize handler accepts reviewed-only startup selections'
    Set-ToolkitBusy $true
    Check (-not $script:controls.IncludeReviewed.IsEnabled -and -not $script:controls.RecommendedButton.IsEnabled -and -not $script:optionChecks.GameMode.IsEnabled) 'Running operation freezes profile/review controls'
    $script:window.Close()
    Write-Host "PASS: $checks Suite audit checks."
} finally {
    if ($link -and (Test-Path -LiteralPath $link)) { [IO.Directory]::Delete($link) }
    if ($key.StartsWith('HKCU:\Software\WindowsPCToolkitTests\') -and (Test-Path -LiteralPath $key)) { Remove-Item -LiteralPath $key -Recurse -Force }
    if ([IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
