#requires -version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('WindowsPCToolkit_Test_'+[guid]::NewGuid().ToString('N'))
$testKey='HKCU:\Software\WindowsPCToolkitTests\'+[guid]::NewGuid().ToString('N')
$checks=0
function Check([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "TEST FAILED: $Message" }
    $script:checks++
}
function Expect-Failure([scriptblock]$Body,[string]$Message) {
    $failed=$false
    try { & $Body } catch { $failed=$true }
    Check $failed $Message
}
[void][IO.Directory]::CreateDirectory($fixture)
[IO.File]::WriteAllText((Join-Path $fixture '.toolkit-test-owner'),$fixture)
try {
    # Check the REAL Windows cmdlet contract before introducing network fakes.
    foreach ($pair in @(
        @('Set-DnsClientServerAddress','InputObject'),@('Set-DnsClientServerAddress','ResetServerAddresses'),
        @('Add-DnsClientDohServerAddress','DohTemplate'),@('Set-DnsClientDohServerAddress','AutoUpgrade'),
        @('Set-DnsClientDohServerAddress','AllowFallbackToUdp'),@('Get-Disk','Number'),@('Get-Partition','DiskNumber'))) {
        Check ((Get-Command $pair[0] -ErrorAction Stop).Parameters.ContainsKey($pair[1])) "Actual Windows cmdlet contract: $($pair -join ' ')"
    }
    Import-Module (Join-Path $root 'Modules\Toolkit.Core.psm1') -ArgumentList (Join-Path $fixture 'State') -Force -DisableNameChecking
    $module=Get-Module Toolkit.Core
    $catalog=@(Get-SuiteActionCatalog)
    Check (@($catalog.Id | Select-Object -Unique).Count -eq $catalog.Count) 'Unique action identifiers'
    Check (@($catalog | Where-Object Default).Count -eq 10) 'Recommended profile includes gaming, cleanup, registry care and AI/consumer debloat'
    Check (@($catalog | Where-Object Default | ForEach-Object Targets | Where-Object { $_.Path -match 'Services|WindowsUpdate|WindowsApps|Device Parameters' }).Count -eq 0) 'Default settings preserve update/security/driver dependencies'
    Expect-Failure { Get-SuitePreview @('invented-action') } 'Unknown action rejected'
    Check (@(Get-SuitePreview @()).Count -eq 0) 'Empty preview remains empty'
    $customTaskWorks=& $module {
        try {
            function script:Get-ScheduledTask {
                [pscustomobject]@{TaskPath='\Fixture\';TaskName='CustomAction';Author='Fixture';State='Ready';Triggers=@([pscustomobject]@{CimClass=[pscustomobject]@{CimClassName='MSFT_TaskLogonTrigger'}});Actions=@([pscustomobject]@{CimClass=[pscustomobject]@{CimClassName='MSFT_TaskComHandlerAction'}})}
            }
            $item=@(Get-SuiteStartupItems | Where-Object Name -eq 'CustomAction')
            return ($item.Count -eq 1 -and $item[0].Target -eq 'COM or custom task action')
        } finally { Remove-Item Function:script:Get-ScheduledTask -ErrorAction Stop }
    }
    Check $customTaskWorks 'Startup inventory supports COM/custom task actions without an Execute property'

    # Real HKCU values + real serialized journal + exact undo, including types.
    New-Item -Path $testKey -Force | Out-Null
    New-ItemProperty -LiteralPath $testKey -Name 'Text' -Value 'original' -PropertyType String | Out-Null
    New-ItemProperty -LiteralPath $testKey -Name 'Expanded' -Value '%TEMP%\literal' -PropertyType ExpandString | Out-Null
    New-ItemProperty -LiteralPath $testKey -Name 'Binary' -Value ([byte[]]@(0,127,255)) -PropertyType Binary | Out-Null
    New-ItemProperty -LiteralPath $testKey -Name 'Multi' -Value ([string[]]@('first','second')) -PropertyType MultiString | Out-Null
    New-ItemProperty -LiteralPath $testKey -Name 'Wide' -Value ([long]4294967297) -PropertyType QWord | Out-Null
    New-ItemProperty -LiteralPath $testKey -Name 'Unicode' -Value 'Grüße 玩家' -PropertyType String | Out-Null
    $run=New-SuiteRun 'Test'
    foreach ($name in @('Text','Expanded','Binary','Multi','Wide','InitiallyAbsent','Unicode')) { Set-SuiteRegistry $run $testKey $name 1 DWord }
    Check ($run.Registry.Count -eq 7) 'Each changed value is journaled'
    $saved=Get-Content -LiteralPath $run.Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @($saved.Registry) | Sort-Object { $_.Before.Name } -Descending) { Undo-SuiteRegistryEntry $entry }
    $actual=Get-Item -LiteralPath $testKey
    Check ($actual.GetValue('Text') -eq 'original') 'String undo'
    Check ($actual.GetValue('Expanded',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -eq '%TEMP%\literal') 'Unexpanded environment string undo'
    Check ($actual.GetValueKind('Expanded') -eq 'ExpandString') 'ExpandString kind retained'
    Check (($actual.GetValue('Binary') -join ',') -eq '0,127,255') 'Binary bytes retained'
    Check (($actual.GetValue('Multi') -join ',') -eq 'first,second') 'MultiString retained'
    Check ($actual.GetValue('Wide') -eq [long]4294967297) 'QWord retained'
    Check ($actual.GetValue('Unicode') -eq 'Grüße 玩家') 'UTF-8 journal preserves non-English values through exact undo'
    Check ($actual.GetValueNames() -notcontains 'InitiallyAbsent') 'Previously absent value removed on undo'
    $run=New-SuiteRun 'Conflict'
    Set-SuiteRegistry $run $testKey 'Text' 'toolkit-value' String
    Set-ItemProperty -LiteralPath $testKey -Name 'Text' -Value 'user-changed-it'
    Expect-Failure { Undo-SuiteRegistryEntry $run.Registry[0] } 'Undo detects intervening user changes'
    Check ((Get-ItemPropertyValue $testKey 'Text') -eq 'user-changed-it') 'Undo preserves intervening user changes'
    $run=New-SuiteRun 'BackupFailure'; $run.Path=Join-Path $fixture 'missing\cannot-write.json'
    Expect-Failure { Set-SuiteRegistry $run $testKey 'Text' 'should-not-be-written' String } 'Backup failure aborts mutation'
    Check ((Get-ItemPropertyValue $testKey 'Text') -eq 'user-changed-it') 'No mutation after backup failure'
    $run=New-SuiteRun 'Removal'
    Set-SuiteRegistry $run $testKey 'Text' $null -Remove
    Check ((Get-Item -LiteralPath $testKey).GetValueNames() -notcontains 'Text') 'Dead-value removal works'
    Undo-SuiteRegistryEntry $run.Registry[0]
    Check ((Get-ItemPropertyValue $testKey 'Text') -eq 'user-changed-it') 'Dead-value removal undo'
    # A crash after a write but before the Applied marker is recoverable.
    $run=New-SuiteRun 'Interrupted'
    Set-SuiteRegistry $run $testKey 'Text' 'interrupted' String
    $run.Registry[0].Status='Pending'
    Undo-SuiteRegistryEntry $run.Registry[0]
    Check ((Get-ItemPropertyValue $testKey 'Text') -eq 'user-changed-it') 'Pending entry recovers after interrupted write'
    Set-ItemProperty -LiteralPath $testKey -Name 'Text' -Value 'changed-after-undo'
    Undo-SuiteRegistryEntry $run.Registry[0]
    Check ((Get-ItemPropertyValue $testKey 'Text') -eq 'changed-after-undo') 'Repeated undo is idempotent and preserves later changes'
    # Exercise the complete orchestrator on disposable keys, including nested
    # startup changes and a mid-action failure. No real Windows profile runs.
    $orchestrator=& $module {
        param($key)
        $savedCatalog=(Get-Item Function:Get-SuiteActionCatalog).ScriptBlock
        $savedStartup=(Get-Item Function:Get-SuiteStartupItems).ScriptBlock
        $savedAdmin=(Get-Item Function:Assert-Administrator).ScriptBlock
        $script:FixtureRegistryKey=$key
        try {
            function script:Assert-Administrator { }
            function script:Get-SuiteActionCatalog {
                [pscustomobject]@{Id='Fixture';Name='Fixture settings';Category='Test';Default=$true;Detail='Disposable test key';Targets=@(@{Path=$script:FixtureRegistryKey;Name='Text';Value='profile';Kind='String'})}
                [pscustomobject]@{Id='FailingFixture';Name='Failing fixture';Category='Test';Default=$false;Detail='Injected failure';Targets=@(@{Path=$script:FixtureRegistryKey;Name='Text';Value='partial';Kind='String'},@{Path='NonexistentProvider:\invalid';Name='Blocked';Value=1})}
            }
            function script:Get-SuiteStartupItems { [pscustomobject]@{Id='fixture-startup';Kind='Startup';Name='Fixture startup';Path=$script:FixtureRegistryKey;ValueName='StartupFixture'} }
            Set-RegistryValueExact $key 'StartupFixture' 'original-startup' String
            $combined=Invoke-SuiteRun -ActionIds @('Fixture') -StartupIds @('fixture-startup')
            $combinedCorrect=($combined.Status -eq 'Completed' -and $combined.Registry.Count -eq 2 -and -not (Get-RegistryValueState $key 'StartupFixture').Exists)
            $undo=Invoke-SuiteUndo -Path $combined.Path
            $undoCorrect=($undo.Status -eq 'Restored' -and (Get-RegistryValueState $key 'StartupFixture').Value -eq 'original-startup' -and (Get-RegistryValueState $key 'Text').Value -eq 'changed-after-undo')
            Set-RegistryValueExact $key 'Text' 'later-user-value' String
            $null=Invoke-SuiteUndo -Path $combined.Path
            $repeatCorrect=((Get-RegistryValueState $key 'Text').Value -eq 'later-user-value')
            Set-RegistryValueExact $key 'Text' 'changed-after-undo' String
            $failed=Invoke-SuiteRun -ActionIds @('FailingFixture')
            [pscustomobject]@{Combined=$combinedCorrect;Undo=$undoCorrect;Repeat=$repeatCorrect;FailureVisible=($failed.Status -eq 'CompletedWithErrors');PartialChangeRolledBack=((Get-RegistryValueState $key 'Text').Value -eq 'changed-after-undo')}
        } finally {
            Set-Item Function:script:Get-SuiteActionCatalog $savedCatalog
            Set-Item Function:script:Get-SuiteStartupItems $savedStartup
            Set-Item Function:script:Assert-Administrator $savedAdmin
        }
    } $testKey
    Check $orchestrator.Combined 'Settings and reviewed startup entries share one operation journal'
    Check $orchestrator.Undo 'Combined operation restores real registry values'
    Check $orchestrator.Repeat 'Repeating a completed operation undo preserves later user settings'
    Check $orchestrator.FailureVisible 'Orchestrator reports a mid-action failure'
    Check $orchestrator.PartialChangeRolledBack 'Orchestrator rolls back a partial registry action'

    # Real package files + real robocopy/hash verification; only AppX/servicing
    # calls are simulated. No installed application or feature is changed.
    $packageRoot=Join-Path $fixture 'Package'
    [void][IO.Directory]::CreateDirectory($packageRoot)
    [IO.File]::WriteAllText((Join-Path $packageRoot 'AppxManifest.xml'),'<fixture/>')
    [IO.File]::WriteAllText((Join-Path $packageRoot 'payload.bin'),'package bytes')
    $debloat=& $module {
        param($packageRoot)
        $savedAdmin=(Get-Item Function:Assert-Administrator).ScriptBlock
        $script:FixturePackageRoot=$packageRoot; $script:FixtureInstalled=$true; $script:FixtureRemovals=0
        $script:FixtureFeature='Enabled'; $script:FixtureFeatureCalls=0
        try {
            function script:Assert-Administrator { }
            function script:Get-AppxPackage {
                param($Name)
                if (-not $Name) {
                    foreach ($packageName in @('Microsoft.Copilot','Microsoft.WindowsStore','Microsoft.GamingServices','Microsoft.XboxApp')) {
                        [pscustomobject]@{Name=$packageName;PackageFullName=$packageName+'_fixture';InstallLocation=$script:FixturePackageRoot;Version='1.0';IsFramework=$false;NonRemovable=$false}
                    }
                    [pscustomobject]@{Name='Microsoft.BingNews';PackageFullName='Framework_fixture';InstallLocation=$script:FixturePackageRoot;Version='1.0';IsFramework=$true;NonRemovable=$false}
                } elseif ($Name -eq 'Microsoft.Copilot' -and $script:FixtureInstalled) { [pscustomobject]@{Name=$Name} }
            }
            function script:Remove-AppxPackage { param($Package) if ($Package -ne 'Microsoft.Copilot_fixture') { throw 'Protected package reached removal' }; $script:FixtureRemovals++; $script:FixtureInstalled=$false }
            function script:Add-AppxPackage { param($Register,[switch]$DisableDevelopmentMode) if (-not (Test-Path -LiteralPath $Register)) { throw 'Missing reinstall manifest' }; $script:FixtureInstalled=$true }
            $available=@(Get-SuiteAppCatalog)
            $preview=@(Get-SuitePreview @('Debloat'))
            $run=Invoke-SuiteRun -ActionIds @('Debloat')
            $copied=[IO.File]::ReadAllText((Join-Path $run.Apps[0].Backup 'payload.bin')) -eq 'package bytes'
            $removed=($run.Status -eq 'Completed' -and $run.Apps.Count -eq 1 -and -not $script:FixtureInstalled)
            $undo=Invoke-SuiteUndo $run.Path
            $reinstalled=($undo.Status -eq 'Restored' -and $script:FixtureInstalled)
            Remove-Item -LiteralPath (Join-Path $packageRoot 'AppxManifest.xml') -Force
            $badBackup=Invoke-SuiteRun -ActionIds @('Debloat')
            $blocked=($badBackup.Status -eq 'CompletedWithErrors' -and $script:FixtureRemovals -eq 1 -and $script:FixtureInstalled)
            $protectedBlocked=$false
            try { $null=Invoke-SuiteRun -ActionIds @('Debloat') -AppIds @('Microsoft.WindowsStore_fixture') } catch { $protectedBlocked=$true }
            function script:Get-CimInstance { [pscustomobject]@{BuildNumber='26100'} }
            function script:Get-WindowsOptionalFeature { param([switch]$Online,$FeatureName) [pscustomobject]@{FeatureName='Recall';State=$script:FixtureFeature} }
            function script:Disable-WindowsOptionalFeature { param([switch]$Online,$FeatureName,[switch]$NoRestart) if (-not $NoRestart) { throw 'Restart must stay explicit' }; $script:FixtureFeatureCalls++; $script:FixtureFeature='Disabled'; [pscustomobject]@{RestartNeeded=$false} }
            function script:Enable-WindowsOptionalFeature { param([switch]$Online,$FeatureName,[switch]$NoRestart) if (-not $NoRestart) { throw 'Restart must stay explicit' }; $script:FixtureFeature='Enabled'; [pscustomobject]@{RestartNeeded=$false} }
            # Fake only reboot-key probes; use native filesystem access elsewhere.
            function script:Test-Path { param($LiteralPath) if ($LiteralPath -like 'HKLM:*') { return $false }; Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath }
            $featureRun=Invoke-SuiteRun -ActionIds @('Recall')
            $featureDisabled=($featureRun.Status -eq 'Completed' -and $featureRun.Features.Count -eq 1 -and $script:FixtureFeature -eq 'Disabled')
            $featureUndo=Invoke-SuiteUndo $featureRun.Path
            $featureRestored=($featureUndo.Status -eq 'Restored' -and $script:FixtureFeature -eq 'Enabled')
            $script:FixtureFeature='Disabled'
            $alreadyDisabled=Invoke-SuiteRun -ActionIds @('Recall')
            [pscustomobject]@{Allowlist=($available.Count -eq 1 -and $available[0].Name -eq 'Microsoft.Copilot');Preview=($preview[0].Details -match 'Installed: Microsoft.Copilot');Copied=$copied;Removed=$removed;Reinstalled=$reinstalled;BackupBlocked=$blocked;ProtectedBlocked=$protectedBlocked;FeatureDisabled=$featureDisabled;FeatureRestored=$featureRestored;FeatureSkipped=($alreadyDisabled.Features.Count -eq 0 -and $script:FixtureFeatureCalls -eq 1 -and $alreadyDisabled.Steps[0].Status -eq 'Skipped')}
        } finally {
            Set-Item Function:script:Assert-Administrator $savedAdmin
            foreach ($name in @('Get-AppxPackage','Remove-AppxPackage','Add-AppxPackage','Get-CimInstance','Get-WindowsOptionalFeature','Disable-WindowsOptionalFeature','Enable-WindowsOptionalFeature','Test-Path')) { Remove-Item ('Function:script:'+$name) -ErrorAction SilentlyContinue }
        }
    } $packageRoot
    Check $debloat.Allowlist 'Copilot is removable; Store, Xbox, Gaming Services and frameworks stay excluded'
    Check $debloat.Preview 'Debloat preview names the installed consumer packages'
    Check $debloat.Copied 'Real robocopy package backup preserves exact file bytes'
    Check $debloat.Removed 'One-click debloat backs up then invokes selected package removal'
    Check $debloat.Reinstalled 'Package journal undo uses the saved manifest for re-registration'
    Check $debloat.BackupBlocked 'Incomplete package backup prevents removal and reports failure'
    Check $debloat.ProtectedBlocked 'Protected app IDs fail preflight before optimization'
    Check $debloat.FeatureDisabled 'Recall feature state is journaled before checked disabling'
    Check $debloat.FeatureRestored 'Recall feature undo restores and verifies original enabled state'
    Check $debloat.FeatureSkipped 'Already disabled Recall is preserved without another servicing call'

    # Real filesystem deletion boundary: recent files, protected names, links.
    $tempRoot=Join-Path $fixture 'Temp'; $outside=Join-Path $fixture 'Outside'
    [void][IO.Directory]::CreateDirectory($tempRoot); [void][IO.Directory]::CreateDirectory($outside)
    [void][IO.Directory]::CreateDirectory((Join-Path $tempRoot 'Documents'))
    foreach ($path in @((Join-Path $tempRoot 'old.tmp'),(Join-Path $tempRoot 'new.tmp'),(Join-Path $tempRoot 'accessed.tmp'),(Join-Path $tempRoot 'Documents\keep.tmp'),(Join-Path $outside 'keep.tmp'))) {
        [IO.File]::WriteAllText($path,'fixture')
        if ($path -notlike '*new.tmp') { [IO.File]::SetLastWriteTime($path,(Get-Date).AddDays(-10)); [IO.File]::SetLastAccessTime($path,(Get-Date).AddDays(-10)) }
    }
    [IO.File]::SetLastAccessTime((Join-Path $tempRoot 'accessed.tmp'),(Get-Date))
    $link=Join-Path $tempRoot 'linked'
    New-Item -ItemType Junction -Path $link -Value $outside -ErrorAction Stop | Out-Null
    Check (@(Get-SuiteOldTempFiles @($tempRoot)).Count -eq 1) 'Age + protected data + junction boundaries'
    Check (-not (Test-SuitePathWithoutLinks (Join-Path $link 'keep.tmp') $tempRoot)) 'Nested junction cannot escape cleanup root'
    Check (-not (Test-SuitePathWithoutLinks (Join-Path $outside 'keep.tmp') $tempRoot)) 'Sibling path cannot escape cleanup root'
    # Re-age only our owned fixture after the read-only enumeration above.
    # Hosted Windows TEMP uses an 8.3 alias; this also exercises normalization.
    $oldFixture=Join-Path $tempRoot 'old.tmp'
    [IO.File]::SetLastWriteTime($oldFixture,(Get-Date).AddDays(-10))
    [IO.File]::SetLastAccessTime($oldFixture,(Get-Date).AddDays(-10))
    $summary=& $module { param($testRoot) $script:TestTempRoot=$testRoot; function script:Get-SuiteTempRoots { @($script:TestTempRoot) }; Invoke-SuiteTempCleanup } $tempRoot
    if (Test-Path -LiteralPath $oldFixture) {
        $diagnostic=& $module { param($path,$testRoot)
            $file=Get-Item -LiteralPath $path -Force
            [pscustomobject]@{Root=$testRoot;FullName=$file.FullName;Roots=@(Get-SuiteTempRoots);LinkBoundary=(Test-SuitePathWithoutLinks $file.FullName $testRoot);Candidates=@(Get-SuiteOldTempFiles | ForEach-Object FullName);Write=$file.LastWriteTime;Access=$file.LastAccessTime;Attributes=[string]$file.Attributes}
        } $oldFixture $tempRoot
        throw "TEST FAILED: Old disposable file actually removed. $summary Diagnostics: $($diagnostic | ConvertTo-Json -Depth 4 -Compress)"
    }
    Check (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'old.tmp'))) 'Old disposable file actually removed'
    Check (Test-Path -LiteralPath (Join-Path $tempRoot 'new.tmp')) 'Recent temp file preserved'
    Check (Test-Path -LiteralPath (Join-Path $tempRoot 'accessed.tmp')) 'Old but recently accessed temp file preserved'
    Check (Test-Path -LiteralPath (Join-Path $tempRoot 'Documents\keep.tmp')) 'Protected data preserved'
    Check (Test-Path -LiteralPath (Join-Path $outside 'keep.tmp')) 'Linked destination preserved'
    Check ($summary -match '^1 aged files removed') 'Cleanup reports actual successful removals'
    [IO.Directory]::Delete($link) # Remove the junction itself, never its target.
    $link=$null
    . (Resolve-SuitePath @('pc-cleaner\PC_Cleaner.ps1','Pc Cleaner\PC_Cleaner.ps1')) -Action Library
    Check (@(Get-CleanCategories | Where-Object { $_.Profile -eq 'Balanced' -and $_.Id -in @('GpuCaches','AiAppCaches','BakFiles','WUCache','RecallData') }).Count -eq 0) 'Legacy cleaner defaults protect game shaders, models, backups and servicing data'
    foreach ($id in @('BakFiles','AiAppCaches','WUCache','RecallData')) {
        $category=Get-CleanCategories | Where-Object Id -eq $id
        Check ((Invoke-CleanCategory $category).Removed -eq 0) "$id remains review-only even through direct category execution"
    }

    # Exercise the real subprocess/file/quoting boundary in a fresh spaced path.
    $fresh=Join-Path $fixture "fresh toolkit's folder 玩家"
    [void][IO.Directory]::CreateDirectory($fresh)
    $friendlyFolders=@{'pc-cleaner'='Pc Cleaner';'pc-gaming-optimizer'='Pc Gaming Optimizer';'dns-encrypted-doh'='Pc Privacy Guard\Optional DNS'}
    foreach ($dir in @('Modules','pc-cleaner','pc-gaming-optimizer','dns-encrypted-doh')) {
        $source=Join-Path $root $dir
        if (-not (Test-Path -LiteralPath $source)) { $source=Join-Path $root $friendlyFolders[$dir] }
        Copy-Item -LiteralPath $source -Destination (Join-Path $fresh $dir) -Recurse
    }
    foreach ($name in @('Toolkit.Worker.ps1','Toolkit.ps1','Toolkit.xaml')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination $fresh }
    $requestPath=Join-Path $fixture 'preview request.json'
    Save-SuiteJson $requestPath ([pscustomobject]@{Operation='Preview';Ids=@('GameMode');Path=$null;DnsAction=$null})
    $native=Invoke-SuiteNative "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $fresh 'Toolkit.Worker.ps1'),'-RequestPath',$requestPath)
    $result=Get-Content -LiteralPath ($requestPath+'.result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Check ($result.Status -eq 'Completed' -and @($result.Data).Count -eq 1) 'Fresh install worker + argument quoting + JSON result'
    $native=Invoke-SuiteNative "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $fresh 'Toolkit.ps1'),'-SmokeTest')
    Check ($native.Output -match 'Dashboard loaded: 55 controls, 19 optimization choices') 'Real WPF dashboard loads in a fresh install'
    # Exercise the actual WPF button -> background job -> DispatcherTimer ->
    # rendered result path. Preview reads settings and changes none of them.
    . (Join-Path $fresh 'Toolkit.ps1') -SmokeTest | Out-Null
    foreach ($uiModule in @(Get-Module Toolkit.Core)) { & $uiModule { param($state) $script:SuiteDataRoot=$state } (Join-Path $fixture 'GuiState') }
    $script:controls.PreviewButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    $script:timer.Start()
    $frame=New-Object Windows.Threading.DispatcherFrame
    $deadline=(Get-Date).AddSeconds(30)
    $poll=New-Object Windows.Threading.DispatcherTimer
    $poll.Interval=[TimeSpan]::FromMilliseconds(50)
    $poll.Add_Tick({ if (-not $script:job -or (Get-Date) -gt $deadline) { $frame.Continue=$false } })
    $poll.Start()
    try { [Windows.Threading.Dispatcher]::PushFrame($frame) }
    finally {
        $poll.Stop(); $script:timer.Stop()
        if ($script:job) { Stop-Job $script:job; Remove-Job $script:job -Force; $script:job=$null }
    }
    Check ($script:controls.StatusText.Text -eq 'Preview only. No Windows settings changed.') 'Real WPF preview button finishes its background worker'
    Check ($script:controls.ResultText.Text -match 'Windows Game Mode' -and $script:controls.OptimizeButton.IsEnabled) 'WPF result text and controls refresh after completion'
    $native=Invoke-SuiteNative "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-Command','[Console]::Error.WriteLine("failure-marker"); exit 7') @(7)
    Check ($native.ExitCode -eq 7 -and $native.Output -match 'failure-marker') 'Native stderr and exit code are captured without pipe deadlock'
    Expect-Failure { Invoke-SuiteNative "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile','-Command','exit 7') } 'Native failure cannot be reported as success'

    # Network fault injection never changes the host's adapters or providers.
    Import-Module (Join-Path $root 'Modules\Network.State.psm1') -Force
    $network=Get-Module Network.State
    $networkFakes={
        $script:Families=@{2=@('old-v4');23=@('old-v6')}
        function script:Get-DnsClientServerAddress { param($InterfaceIndex) $script:LastIndex=$InterfaceIndex; [pscustomobject]@{AddressFamily=2}; [pscustomobject]@{AddressFamily=23} }
        function script:Set-DnsClientServerAddress { param($InputObject,$ServerAddresses,[switch]$ResetServerAddresses) $script:Families[[int]$InputObject.AddressFamily]=if ($ResetServerAddresses) { @() } else { @($ServerAddresses) } }
    }
    & $network $networkFakes
    Set-AdapterDnsFamilies -Index 7 -IPv4 @() -IPv6 @('2001:db8::9')
    $families=& $network { $script:Families }
    Check (@($families[2]).Count -eq 0 -and ($families[23] -join ',') -eq '2001:db8::9') 'IPv4 automatic + IPv6 static remains distinct'
    Set-AdapterDnsFamilies -Index 7 -IPv4 @('9.9.9.9') -IPv6 @()
    $families=& $network { $script:Families }
    Check (($families[2] -join ',') -eq '9.9.9.9' -and @($families[23]).Count -eq 0) 'IPv4 static + IPv6 automatic remains distinct'
    . (Join-Path $root 'dns-encrypted-doh\DNS_Manager.ps1') -Action Library
    Check ($Providers.Count -eq 2 -and $Providers.Contains('Quad9') -and $Providers.Contains('AdGuard')) 'Only ongoing DNS providers are offered'
    Expect-Failure { Set-Provider MullvadAdBlock } 'Retiring Mullvad apply fails before initialization or DNS mutation'
    $StateRoot=Join-Path $fixture 'Dns'; [void][IO.Directory]::CreateDirectory($StateRoot)
    function Assert-Admin { }
    function Initialize-State { }
    $script:Doh=@{}
    function Get-DnsClientDohServerAddress { foreach ($value in $script:Doh.Values) { $value } }
    function Set-DnsClientDohServerAddress { param($ServerAddress,$DohTemplate,$AllowFallbackToUdp,$AutoUpgrade) $script:Doh[$ServerAddress]=[pscustomobject]@{ServerAddress=$ServerAddress;DohTemplate=$DohTemplate;AllowFallbackToUdp=$AllowFallbackToUdp;AutoUpgrade=$AutoUpgrade} }
    function Add-DnsClientDohServerAddress { param($ServerAddress,$DohTemplate,$AllowFallbackToUdp,$AutoUpgrade) if ($script:Doh.ContainsKey($ServerAddress)) { throw 'Duplicate DoH entry' }; Set-DnsClientDohServerAddress @PSBoundParameters }
    function Remove-DnsClientDohServerAddress { throw 'Existing DoH entry must be updated in place, never deleted first.' }
    Set-DnsClientDohServerAddress '9.9.9.9' 'https://old.example/dns-query' $true $false
    Add-DohEntry '9.9.9.9' 'https://dns.quad9.net/dns-query' $false $true
    Check ($script:Doh['9.9.9.9'].DohTemplate -eq 'https://dns.quad9.net/dns-query' -and -not $script:Doh['9.9.9.9'].AllowFallbackToUdp) 'Existing built-in DoH entry updated without deletion'
    foreach ($server in @($Providers.Quad9.V4)+@($Providers.Quad9.V6)) { Set-DnsClientDohServerAddress $server $Providers.Quad9.Template $false $true }
    function Get-Adapters { [pscustomobject]@{Name='Fixture NIC';ifIndex=7} }
    function Test-AdapterIPv6 { $false }
    function Get-DnsClientServerAddress { param($InterfaceIndex) [pscustomobject]@{ServerAddresses=@('9.9.9.9','149.112.112.112')} }
    function Resolve-DnsName { param($Name,$Type,[switch]$DnsOnly) if ($Type -eq 'TXT') { throw 'Simulated live transport test outage' }; [pscustomobject]@{IPAddress='192.0.2.1'} }
    Check (-not (Test-Configuration Quad9)) 'An unavailable live transport check cannot claim verified encryption'
    # DNS library imports the shared module afresh; rebind its mutation fakes.
    $network=Get-Module Network.State
    & $network $networkFakes
    $fixtureGuid=[guid]::NewGuid()
    $legacyDns=[pscustomobject]@{Schema=3;Adapters=@([pscustomobject]@{Name='Original NIC';InterfaceGuid=$fixtureGuid.ToString();InterfaceIndex=7;Automatic=$false;StaticIPv4=@('9.9.9.9');StaticIPv6=@()});Encryption=@();TouchedServers=@();CurrentProvider=$null}
    $legacyPath=Join-Path $fixture 'legacy-dns.json'; Save-SuiteJson $legacyPath $legacyDns
    function Get-NetAdapter { [pscustomobject]@{Name='Renamed NIC';InterfaceGuid=$fixtureGuid;ifIndex=99} }
    function Get-StaticDnsServers { param($Adapter) $state=& $network { $script:Families }; [pscustomobject]@{IPv4=@($state[2]);IPv6=@($state[23])} }
    function Clear-DnsClientCache { }
    & { Set-StrictMode -Version 2.0; Restore-Snapshot -Path $legacyPath }
    Check ((& $network { $script:LastIndex }) -eq 99) 'Legacy DNS backup restores by GUID despite changed interface index'
    Check (((& $network { $script:Families[2] }) -join ',') -eq '9.9.9.9' -and @((& $network { $script:Families[23] })).Count -eq 0) 'Legacy schema without computer field and empty encryption list retains per-family DNS mode'
    $legacyDns.Adapters[0].InterfaceGuid=[guid]::NewGuid().ToString(); Save-SuiteJson $legacyPath $legacyDns
    $missingAdapterError=''
    try { Restore-Snapshot -Path $legacyPath } catch { $missingAdapterError=$_.Exception.Message }
    Check ($missingAdapterError -like 'Original adapter no longer exists*') 'Missing original adapter fails DNS restore preflight before mutations'
    Import-Module (Resolve-SuitePath @('pc-gaming-optimizer\Modules\Optimizer.Core.psm1','Pc Gaming Optimizer\Modules\Optimizer.Core.psm1')) -Force -DisableNameChecking
    $gameModule=Get-Module Optimizer.Core
    $restoredPriority=& $gameModule {
        $script:FixtureGame=[pscustomobject]@{Id=42;ProcessName='FixtureGame';MainWindowTitle='Fixture';PriorityClass='Normal';HasExited=$false}
        $script:Reads=0
        function script:Get-Process { param($Id) $script:FixtureGame }
        function script:Read-Host { param($Prompt) $script:Reads++; if ($script:Reads -eq 1) { '42' } else { throw 'Simulated interrupted game session' } }
        function script:Enable-StayAwake { }
        function script:Disable-StayAwake { }
        Invoke-GameBooster | Out-Null
        $script:FixtureGame.PriorityClass
    }
    Check ($restoredPriority -eq 'Normal') 'Game priority is restored in finally after interruption'
    # Load only the repair function's AST, avoiding the console's bootstrap.
    # Inject failed stops, failed restarts and partial renames without touching
    # the host's services or update folders.
    $fixerSource=Join-Path $root 'pc-corruption-fixer\PC_Fixer.ps1'
    if (-not (Test-Path -LiteralPath $fixerSource)) { $fixerSource=Join-Path $root 'Pc Corruption Fixer\PC_Fixer.ps1' }
    $fixerAst=[Management.Automation.Language.Parser]::ParseFile($fixerSource,[ref]$null,[ref]$null)
    $updateDefinition=$fixerAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-WindowsUpdateRepair'},$false).Extent.Text
    foreach ($scenario in @('StopFailure','RenameFailure','RestartFailure','Success')) {
        $repairResult=& {
            param($definition,$scenario)
            Invoke-Expression $definition
            $script:Results=@{}; $script:HasFailure=$false
            $script:FixtureServices=@{bits='Running';wuauserv='Running';cryptsvc='Stopped';DoSvc='Stopped'}
            $script:FixtureRenameCount=0; $script:FixtureStarts=@(); $script:FixtureScenario=$scenario
            function Test-PendingReboot { [pscustomobject]@{Pending=$false;Reasons=@()} }
            function Read-Host { 'y' }
            function Write-StepHeader { }
            function Write-Status { }
            function Enable-StayAwake { }
            function Disable-StayAwake { }
            function Get-Elapsed { 'fixture' }
            function Get-Service {
                param($Name)
                $service=[pscustomobject]@{Status=$script:FixtureServices[$Name]}
                $service | Add-Member ScriptMethod WaitForStatus { param($status,$timeout) if ($this.Status -ne $status) { throw 'Fixture service did not reach requested status' } }
                $service
            }
            function Stop-Service { param($Name,[switch]$Force) if ($script:FixtureScenario -eq 'StopFailure' -and $Name -eq 'wuauserv') { throw 'Injected stop failure' }; $script:FixtureServices[$Name]='Stopped' }
            function Start-Service { param($Name) $script:FixtureStarts+=,$Name; if ($script:FixtureScenario -eq 'RestartFailure' -and $Name -eq 'bits') { throw 'Injected restart failure' }; $script:FixtureServices[$Name]='Running' }
            function Get-Item { [pscustomobject]@{Attributes=[IO.FileAttributes]::Directory} }
            function Rename-Item { param($LiteralPath,$NewName) if ($script:FixtureScenario -eq 'RenameFailure' -and $script:FixtureRenameCount -eq 1) { throw 'Injected second cache rename failure' }; $script:FixtureRenameCount++; }
            # Cache read-back follows the successful rename for each folder.
            function Test-Path {
                param($LiteralPath)
                if ($LiteralPath -like '*.pcfixer.*') { return $true }
                if ($LiteralPath -like '*SoftwareDistribution') { return ($script:FixtureRenameCount -eq 0) }
                if ($LiteralPath -like '*catroot2') { return ($script:FixtureRenameCount -lt 2) }
                throw 'Unexpected fixture path'
            }
            Invoke-WindowsUpdateRepair
            [pscustomobject]@{Status=$script:Results.WinUpdate;Failed=$script:HasFailure;Renames=$script:FixtureRenameCount;Starts=@($script:FixtureStarts);Services=$script:FixtureServices}
        } $updateDefinition $scenario
        Check (($repairResult.Status -like 'COMPLETED*') -eq ($scenario -eq 'Success')) "Update repair reports actual $scenario outcome"
        Check ($repairResult.Starts -notcontains 'cryptsvc' -and $repairResult.Starts -notcontains 'DoSvc') "Update repair preserves stopped services during $scenario"
        if ($scenario -eq 'StopFailure') { Check ($repairResult.Renames -eq 0 -and $repairResult.Services.bits -eq 'Running') 'Failed service stop prevents all cache mutation and restores prior services' }
    }
    $privacySource=Join-Path $root 'pc-privacy-guard\PC_Privacy.ps1'
    if (-not (Test-Path -LiteralPath $privacySource)) { $privacySource=Join-Path $root 'Pc Privacy Guard\PC_Privacy.ps1' }
    $privacyAst=[Management.Automation.Language.Parser]::ParseFile($privacySource,[ref]$null,[ref]$null)
    $privacyDefinitions=@($privacyAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Get-RegState','Set-RegExact','Restore-RegState','Restore-LatestSnapshot')},$false) | ForEach-Object { $_.Extent.Text }) -join "`n"
    $privacyChecks=& {
        param($definitions,$key,$fixture)
        Invoke-Expression $definitions
        function Assert-Admin { }
        function Initialize-State { }
        function Get-LatestSnapshot { Join-Path $fixture 'privacy.json' }
        $script:FixturePrivacySuccess=$false
        function Write-Status { param($Kind,$Message) if ($Kind -eq 'OK') { $script:FixturePrivacySuccess=$true } }
        $before=Get-RegState $key 'Expanded'
        Set-RegExact $key 'Expanded' 'temporary' String
        Restore-RegState ($before | ConvertTo-Json | ConvertFrom-Json)
        $typed=((Get-RegState $key 'Expanded').Kind -eq 'ExpandString' -and (Get-RegState $key 'Expanded').Value -eq '%TEMP%\literal')
        $snapshot=[pscustomobject]@{Computer=$env:COMPUTERNAME;User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;Registry=@();Services=@([pscustomobject]@{Name='FixtureService';StartMode='Auto';State='Running'});Tasks=@()}
        Save-SuiteJson (Get-LatestSnapshot) $snapshot
        function Set-Service { }
        function Start-Service { throw 'Injected service restart failure' }
        function Stop-Service { throw 'Unexpected service mutation' }
        $failure=''
        try { Restore-LatestSnapshot } catch { $failure=$_.Exception.Message }
        [pscustomobject]@{Typed=$typed;Failed=($failure -eq 'Injected service restart failure' -and -not $script:FixturePrivacySuccess)}
    } $privacyDefinitions $testKey $fixture
    Check $privacyChecks.Typed 'Privacy undo verifies exact registry type and literal environment value'
    Check $privacyChecks.Failed 'Privacy undo exposes service restore failure instead of claiming exact success'
    $aiDefinitions=@($fixerAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Get-AiRegistryEntryState','Restore-AiFeatureSnapshot')},$false) | ForEach-Object { $_.Extent.Text }) -join "`n"
    $aiChecks=& {
        param($definitions,$key,$fixture)
        Invoke-Expression $definitions
        $state=Get-AiRegistryEntryState $key 'Expanded'
        $snapshot=[pscustomobject]@{Schema=1;Computer=$env:COMPUTERNAME;User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;Entries=@($state)}
        $path=Join-Path $fixture 'ai-policy.json'; Save-SuiteJson $path $snapshot
        $script:Results=@{}; $script:HasFailure=$false
        function Write-Status { }
        function New-ItemProperty { throw 'Injected denied registry restore' }
        Set-ItemProperty -LiteralPath $key -Name 'Expanded' -Value 'changed'
        $reportedFailure=(-not (Restore-AiFeatureSnapshot $path) -and $script:HasFailure)
        function Get-Item { throw 'Injected denied registry read' }
        $readFailure=''
        try { $null=Get-AiRegistryEntryState $key 'Expanded' } catch { $readFailure=$_.Exception.Message }
        [pscustomobject]@{RestoreFailed=$reportedFailure;ReadFailed=($readFailure -match 'Could not read AI policy state')}
    } $aiDefinitions $testKey $fixture
    Check $aiChecks.RestoreFailed 'AI policy undo returns failure when a saved value cannot be restored'
    Check $aiChecks.ReadFailed 'Unreadable AI registry state aborts snapshots rather than recording absence'
    Write-Host "PASS: $checks regression and real-boundary checks." -ForegroundColor Green
} finally {
    if ($link -and (Test-Path -LiteralPath $link)) { [IO.Directory]::Delete($link) }
    if ($testKey.StartsWith('HKCU:\Software\WindowsPCToolkitTests\') -and (Test-Path -LiteralPath $testKey)) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    $marker=Join-Path $fixture '.toolkit-test-owner'
    if ((Test-Path -LiteralPath $marker) -and [IO.File]::ReadAllText($marker) -eq $fixture -and [IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
