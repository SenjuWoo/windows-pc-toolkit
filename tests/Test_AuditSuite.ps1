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
    Initialize-SuiteState
    $fixtureAcl=New-Object Security.AccessControl.DirectorySecurity
    $fixtureAcl.SetSecurityDescriptorSddlForm((Get-Acl -LiteralPath (Get-SuiteDataRoot)).GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access),[Security.AccessControl.AccessControlSections]::Access)
    Set-Acl -LiteralPath $fixture -AclObject $fixtureAcl
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
    function Rejects([scriptblock]$Body,[string]$Pattern,[string]$Message) {
        $cause=$null; try { & $Body | Out-Null } catch { $cause=$_.Exception.Message }
        Check ($cause -like $Pattern) "$Message; actual cause: $cause"
    }
    # Hand-authored recovery documents must fail before any legitimate entry
    # is restored. All real registry targets here belong to this fixture.
    $run=New-SuiteRun 'Optimize'
    $before=[pscustomobject]@{Path=$key;Name='Text';Exists=$true;Kind='String';Value='untrusted journal'}
    $after=[pscustomobject]@{Path=$key;Name='Text';Exists=$true;Kind='String';Value='ORIGINAL'}
    [void]$run.Registry.Add([pscustomobject]@{Before=$before;After=$after;Status='Applied'})
    Save-SuiteJson $run.Path $run
    Rejects { Invoke-SuiteUndo $run.Path } '*outside toolkit settings*' 'A same-account arbitrary registry journal is rejected'
    Check ((Get-ItemPropertyValue $key Text) -ceq 'ORIGINAL') 'Rejected recovery leaves the real fixture value intact'
    & $module {
        param($key)
        $script:AuditKey=$key
        $script:SavedUndoTargets=(Get-Item Function:Get-SuiteRegistryUndoTargets).ScriptBlock
        function script:Get-SuiteRegistryUndoTargets { [pscustomobject]@{Path=$script:AuditKey;Name='Text';Exists=$true;Kind='String';Value='ORIGINAL'} }
    } $key
    try {
        [void]$run.Registry.Add($run.Registry[0]); Save-SuiteJson $run.Path $run
        Rejects { Invoke-SuiteUndo $run.Path } '*duplicate registry targets*' 'Duplicate registry records fail preflight'
        $run.Registry.RemoveAt(1)
        [void]$run.Features.Add([pscustomobject]@{Name='UnreviewedFeature';Before='Enabled';After='Disabled';Status='Applied'})
        Save-SuiteJson $run.Path $run
        Rejects { Invoke-SuiteUndo $run.Path } '*Only the saved Recall feature*' 'Unknown feature fails whole-journal preflight'
        Check ((Get-ItemPropertyValue $key Text) -ceq 'ORIGINAL') 'A later invalid feature prevents an earlier valid registry restore'
        $run.Features.Clear(); $run.Registry[0].After.Kind='DWord'; $run.Registry[0].After.Value='7'
        Save-SuiteJson $run.Path $run
        Rejects { Invoke-SuiteUndo $run.Path } '*Invalid registry DWORD*' 'String-shaped numeric backups cannot pass typed preflight'
        $run.Registry[0].After.Kind='String'; $run.Registry[0].After.Value='ORIGINAL'; $run.Registry[0].After.Name='Other'
        Save-SuiteJson $run.Path $run
        Rejects { Invoke-SuiteUndo $run.Path } '*Registry backup target/status changed*' 'Before and after must refer to the same registry target'
        $run.Registry[0].After.Name='Text'
        [void]$run.Tasks.Add([pscustomobject]@{Path='\Microsoft\Fixture\';Name='Protected';Enabled=$true;Status='Applied'})
        Save-SuiteJson $run.Path $run
        Rejects { Invoke-SuiteUndo $run.Path } '*protected task recovery target*' 'Windows task entries cannot enter a consumer-startup recovery journal'
        Check ((Get-ItemPropertyValue $key Text) -ceq 'ORIGINAL') 'Invalid typed/task journals performed no registry write'
    } finally { & $module { Set-Item Function:script:Get-SuiteRegistryUndoTargets $script:SavedUndoTargets } }
    $appRun=New-SuiteRun 'Debloat'
    $backup=Join-Path (Get-SuiteDataRoot) ('AppBackups\'+$appRun.Id+'\Microsoft.Copilot_fixture')
    [void][IO.Directory]::CreateDirectory($backup)
    $manifest=Join-Path $backup 'AppxManifest.xml'; $payload=Join-Path $backup 'payload.txt'
    [IO.File]::WriteAllText($manifest,'fixture-manifest'); [IO.File]::WriteAllText($payload,'fixture-payload')
    $manifestRecord=[pscustomobject]@{RelativePath='AppxManifest.xml';Hash=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash}
    $payloadRecord=[pscustomobject]@{RelativePath='payload.txt';Hash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash}
    $appEntry=[pscustomobject]@{Name='Microsoft.Copilot';Package='Microsoft.Copilot_fixture';Backup=$backup;Files=@($payloadRecord,$payloadRecord);Status='Removed'}
    [void]$appRun.Apps.Add($appEntry); Save-SuiteJson $appRun.Path $appRun
    Rejects { Invoke-SuiteUndo $appRun.Path } '*Duplicate or escaping app backup*' 'Duplicate hashes cannot hide an unchecked manifest'
    $appEntry.Files=@($payloadRecord); Save-SuiteJson $appRun.Path $appRun
    Rejects { Invoke-SuiteUndo $appRun.Path } '*omits its manifest*' 'The manifest must be included in the saved hash inventory'
    $appEntry.Files=@($manifestRecord,$payloadRecord); $appEntry.Name='Microsoft.WindowsStore'; Save-SuiteJson $appRun.Path $appRun
    Rejects { Invoke-SuiteUndo $appRun.Path } '*protected app recovery target*' 'Protected packages cannot enter app recovery'
    $appEntry.Name='Microsoft.Copilot'
    $appEntry.Backup=Join-Path (Get-SuiteDataRoot) 'AppBackups\another-operation'; Save-SuiteJson $appRun.Path $appRun
    Rejects { Invoke-SuiteUndo $appRun.Path } '*does not belong to this operation*' 'App backups must belong to the exact operation and package'
    $appEntry.Backup=$backup; Save-SuiteJson $appRun.Path $appRun
    [void]$appRun.Apps.Add($appEntry); Save-SuiteJson $appRun.Path $appRun
    Rejects { Invoke-SuiteUndo $appRun.Path } '*duplicate app targets*' 'Duplicate app records fail preflight'
    $appRun.Apps.RemoveAt(1); Save-SuiteJson $appRun.Path $appRun
    $inventoryResult=& $module {
        param($path,$payload)
        try {
            $script:AuditRegisterCalls=0
            function script:Get-AppxPackage { param($Name) }
            function script:Add-AppxPackage { param($Register,[switch]$DisableDevelopmentMode) $script:AuditRegisterCalls++ }
            Rename-Item -LiteralPath $payload -NewName 'unrecorded.txt'
            $undo=Invoke-SuiteUndo $path
            [pscustomobject]@{Status=$undo.Status;Message=$undo.Message;Calls=$script:AuditRegisterCalls}
        } finally { Remove-Item Function:script:Get-AppxPackage,Function:script:Add-AppxPackage }
    } $appRun.Path $payload
    Check ($inventoryResult.Status -eq 'UndoNeedsAttention' -and $inventoryResult.Message -like '*unrecorded file*' -and $inventoryResult.Calls -eq 0) 'Same-count replacement files fail exact inventory before app registration'
    $taskResult=& $module {
        $savedTask=(Get-Item Function:Get-SuiteTask).ScriptBlock
        try {
            $script:AuditTask=[pscustomobject]@{Author='Fixture';Settings=[pscustomobject]@{Enabled=$false};Triggers=@([pscustomobject]@{CimClass=[pscustomobject]@{CimClassName='MSFT_TaskLogonTrigger'}})}
            function script:Get-SuiteTask { param($Path,$Name) $script:AuditTask }
            function script:Enable-ScheduledTask { param($InputObject) $InputObject.Settings.Enabled=$true }
            $taskRun=New-SuiteRun 'Startup'
            [void]$taskRun.Tasks.Add([pscustomobject]@{Path='\Fixture\';Name='[literal]';Enabled=$true;Status='Pending'})
            [void]$taskRun.Tasks.Add($taskRun.Tasks[0]); Save-SuiteJson $taskRun.Path $taskRun
            $duplicateRejected=$false
            try { Invoke-SuiteUndo $taskRun.Path | Out-Null } catch { $duplicateRejected=$_.Exception.Message -like '*duplicate task targets*' }
            if (-not $duplicateRejected -or $script:AuditTask.Settings.Enabled) { throw 'Duplicate task records did not fail before mutation.' }
            $taskRun.Tasks.RemoveAt(1)
            Save-SuiteJson $taskRun.Path $taskRun
            $undo=Invoke-SuiteUndo $taskRun.Path
            $restored=$undo.Status -eq 'Restored' -and $script:AuditTask.Settings.Enabled
            function script:Get-SuiteTask { throw 'Fixture task no longer exists.' }
            $noop=Invoke-SuiteUndo $taskRun.Path
            [pscustomobject]@{Restored=$restored;Noop=($noop.Status -eq 'Restored')}
        } finally { Set-Item Function:script:Get-SuiteTask $savedTask; Remove-Item Function:script:Enable-ScheduledTask }
    }
    Check $taskResult.Restored 'Valid interrupted third-party startup-task journals still restore exact task objects'
    Check $taskResult.Noop 'Completed task undo remains a no-op after the task is removed'
    $insecure=Join-Path $fixture 'InsecureState'; [void][IO.Directory]::CreateDirectory($insecure)
    $acl=Get-Acl -LiteralPath $insecure
    $rule=New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-1-0')),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.AddAccessRule($rule); Set-Acl -LiteralPath $insecure -AclObject $acl
    & $module { param($target) $script:SavedDataRoot=$script:SuiteDataRoot; $script:SuiteDataRoot=$target } $insecure
    try {
        Rejects { Initialize-SuiteState } '*writable by another account*' 'Existing insecure state cannot be silently trusted after ACL changes'
        Check (-not (Test-Path -LiteralPath (Join-Path $insecure 'Runs'))) 'Untrusted state is rejected before creating child storage'
    } finally { & $module { $script:SuiteDataRoot=$script:SavedDataRoot } }
    $fileRun=New-SuiteRun 'Optimize'; $originalAcl=Get-Acl -LiteralPath $fileRun.Path
    $fileAcl=Get-Acl -LiteralPath $fileRun.Path
    $fileAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-1-0')),'Write','Allow')))
    Set-Acl -LiteralPath $fileRun.Path -AclObject $fileAcl
    try { Rejects { Invoke-SuiteUndo $fileRun.Path } '*writable by another account*' 'An unsafe individual journal is rejected even beneath a protected root' }
    finally { Set-Acl -LiteralPath $fileRun.Path -AclObject $originalAcl }
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
    Check ($result.Status -eq 'Failed' -and $result.Message -like '*Invalid JSON*') 'Malformed request produces its JSON failure result from a private request folder'
    $originalRequestAcl=Get-Acl -LiteralPath $request
    $requestAcl=Get-Acl -LiteralPath $request
    $requestAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-1-0')),'Write','Allow')))
    Set-Acl -LiteralPath $request -AclObject $requestAcl
    try {
        Fails { Invoke-SuiteNative "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-File',(Join-Path $root 'Toolkit.Worker.ps1'),'-RequestPath',$request) } 'Unsafe request file fails the worker'
        $result=Get-Content -LiteralPath ($request+'.result.json') -Raw | ConvertFrom-Json
        Check ($result.Message -like '*writable by another account*') 'Worker rejects unsafe request-file permissions before reading its operation'
    } finally { Set-Acl -LiteralPath $request -AclObject $originalRequestAcl }
    $unsafeRequests=Join-Path $fixture 'UnsafeRequests'; [void][IO.Directory]::CreateDirectory($unsafeRequests)
    $unsafeRequest=Join-Path $unsafeRequests 'request.json'; [IO.File]::WriteAllText($unsafeRequest,'invalid json')
    [IO.File]::WriteAllText(($unsafeRequest+'.result.json'),'kept fixture result')
    $originalParentAcl=Get-Acl -LiteralPath $unsafeRequests
    $parentAcl=Get-Acl -LiteralPath $unsafeRequests
    $parentAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-1-0')),'FullControl','Allow')))
    $previousResult=Get-Content -LiteralPath ($unsafeRequest+'.result.json') -Raw
    Set-Acl -LiteralPath $unsafeRequests -AclObject $parentAcl
    try {
        Rejects { Invoke-SuiteNative "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-File',(Join-Path $root 'Toolkit.Worker.ps1'),'-RequestPath',$unsafeRequest) } '*writable by another account*' 'Worker rejects a replaceable request beneath an unsafe directory'
        Check ((Get-Content -LiteralPath ($unsafeRequest+'.result.json') -Raw) -ceq $previousResult) 'Worker failure does not write output through unsafe storage'
    } finally { Set-Acl -LiteralPath $unsafeRequests -AclObject $originalParentAcl }
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
        Check ($line.Message.Length -eq 4096 -and $line.Version -eq (Get-SuiteVersion)) 'Failure causes are bounded and versioned with debug off'
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
