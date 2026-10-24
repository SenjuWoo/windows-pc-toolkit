# OneDrive folder gate. Proves the toolkit refuses the lock and the location
# restore, preserves existing files, and refuses uncertain folder locations.
#requires -version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('WindowsPCToolkit_OneDrive_'+[guid]::NewGuid().ToString('N'))
$testKey='HKCU:\Software\WindowsPCToolkitTests\'+[guid]::NewGuid().ToString('N')
$userKey=Join-Path $testKey 'User Shell Folders'
$shellKey=Join-Path $testKey 'Shell Folders'
$policyKey=Join-Path $testKey 'Policy'
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
function Set-RegValue([string]$Key,[string]$Name,[string]$Value,[string]$Kind) {
    if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force | Out-Null }
    New-ItemProperty -LiteralPath $Key -Name $Name -Value $Value -PropertyType $Kind -Force | Out-Null
}
function Get-RegValue([string]$Key,[string]$Name) {
    if (-not (Test-Path -LiteralPath $Key)) { return $null }
    $item=Get-Item -LiteralPath $Key
    if ($item.GetValueNames() -notcontains $Name) { return $null }
    [pscustomobject]@{ Kind=$item.GetValueKind($Name).ToString(); Value=$item.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
}
[void][IO.Directory]::CreateDirectory($fixture)
try {
    Import-Module (Join-Path $root 'Modules\Toolkit.Core.psm1') -ArgumentList (Join-Path $fixture 'State') -Force -DisableNameChecking
    Initialize-SuiteState
    $profile=Join-Path $fixture 'Profile'
    [void][IO.Directory]::CreateDirectory($profile)
    function Set-AllLocal {
        foreach ($known in @(Get-SuiteKnownFolderCatalog)) {
            $path=Join-Path $profile $known.Relative
            [void][IO.Directory]::CreateDirectory($path)
            Set-RegValue $userKey $known.ValueName $path 'String'
            Set-RegValue $shellKey $known.ValueName $path 'String'
        }
    }
    function Get-FixtureReport([string]$Executable,[switch]$CountCloudOnly,[int]$CloudLimit=2000) {
        Get-SuiteOneDriveReport -UserShellKey $userKey -ShellKey $shellKey -PolicyKey $policyKey -ProfilePath $profile -OneDriveRoots @() -OneDriveExecutable $Executable -CountCloudOnly:$CountCloudOnly -CloudLimit $CloudLimit
    }
    Set-AllLocal
    $local=Get-FixtureReport ''
    Check ($local.PolicyAllowed -and -not $local.UninstallAllowed -and -not $local.RestoreAllowed) 'Local folders with no OneDrive app can be locked and are not a restore'
    Check (@($local.Folders | Where-Object Status -eq 'On this PC').Count -eq 5) 'All five folders report On this PC'

    $documents=Join-Path $profile 'OneDrive\Documents'
    [void][IO.Directory]::CreateDirectory($documents)
    $kept=Join-Path $documents 'keep.txt'
    [IO.File]::WriteAllText($kept,'still here')
    Set-RegValue $userKey 'Personal' $documents 'String'
    Set-RegValue $shellKey 'Personal' $documents 'String'
    $redirected=Get-FixtureReport (Join-Path $fixture 'OneDrive.exe')
    Check (-not $redirected.PolicyAllowed -and -not $redirected.UninstallAllowed -and -not $redirected.RestoreAllowed) 'Installed OneDrive with Documents redirected blocks lock, uninstall and registry restore'
    Check ($redirected.PolicyBlock -match 'Only on my PC' -and $redirected.PolicyBlock -match 'Documents') 'Block tells the user to choose Only on my PC before uninstall'
    $run=New-SuiteRun 'Optimize'
    Expect-Failure { Invoke-SuiteKnownFolderLock -Run $run -UserShellKey $userKey -ShellKey $shellKey -PolicyKey $policyKey -ProfilePath $profile -OneDriveRoots @() -OneDriveExecutable '' } 'Lock throws while a folder is in OneDrive'
    Check ($null -eq (Get-RegValue $policyKey 'KFMBlockOptIn')) 'Refused lock does not write KFMBlockOptIn'
    Expect-Failure { Invoke-SuiteOneDriveFolderRestore -UserShellKey $userKey -ShellKey $shellKey -PolicyKey $policyKey -ProfilePath $profile -OneDriveRoots @() -OneDriveExecutable (Join-Path $fixture 'OneDrive.exe') } 'Restore throws while OneDrive.exe is still present'
    Check ((Get-RegValue $userKey 'Personal').Value -eq $documents) 'Refused restore leaves the OneDrive path in place'

    $personal=Get-FixtureReport ''
    # A missing destination used to be silently written and reported as a successful restore.
    [IO.Directory]::Delete((Join-Path $profile 'Documents'))
    Expect-Failure { Invoke-SuiteOneDriveFolderRestore -UserShellKey $userKey -ShellKey $shellKey -PolicyKey $policyKey -ProfilePath $profile -OneDriveRoots @() -OneDriveExecutable '' } 'Automatic registry restore is retired even when OneDrive is absent'
    Check (-not $personal.RestoreAllowed -and -not $personal.UninstallAllowed) 'A stranded folder requires guided recovery, not an automated rewrite'
    Check ((Get-RegValue $userKey 'Personal').Value -eq $documents -and (Get-RegValue $shellKey 'Personal').Value -eq $documents) 'Refused restore leaves both original locations intact'
    Check ((Get-Content -LiteralPath $kept -Raw) -eq 'still here') 'Refused restore preserves the file left in OneDrive'
    $legacy=New-SuiteRun 'OneDriveFolders'
    Expect-Failure { Invoke-SuiteUndo -Path $legacy.Path } 'Old folder reports remain guarded against an automatic redirection undo'

    Set-AllLocal
    Set-RegValue $policyKey 'KFMBlockOptOut' '1' 'DWord'
    $forced=Get-FixtureReport ''
    Check (-not $forced.PolicyAllowed -and $forced.PolicyBlock -match 'KFMBlockOptOut') 'A force-to-OneDrive policy blocks the local lock'
    Remove-ItemProperty -LiteralPath $policyKey -Name 'KFMBlockOptOut'
    Set-RegValue $policyKey 'KFMSilentOptIn' '1111-2222-3333-4444' 'String'
    Check (-not (Get-FixtureReport '').PolicyAllowed) 'Silent known-folder move blocks the local lock'
    Remove-ItemProperty -LiteralPath $policyKey -Name 'KFMSilentOptIn'
    $locked=Invoke-SuiteKnownFolderLock -Run (New-SuiteRun 'Optimize') -UserShellKey $userKey -ShellKey $shellKey -PolicyKey $policyKey -ProfilePath $profile -OneDriveRoots @() -OneDriveExecutable ''
    $policy=Get-RegValue $policyKey 'KFMBlockOptIn'
    Check ($locked.PolicyAllowed -and $null -ne $policy -and [int]$policy.Value -eq 1 -and $policy.Kind -eq 'DWord') 'Lock writes KFMBlockOptIn 1 only after folders are local'

    Set-RegValue $userKey 'Personal' (Join-Path $profile 'OneDrive - Personal\Documents') 'String'
    Check (((Get-FixtureReport '').Folders | Where-Object Folder -eq 'Documents').UserClass -eq 'OneDrive') 'OneDrive - Personal is treated as OneDrive'
    Set-RegValue $userKey 'Personal' (Join-Path $profile 'OneDriveNotes') 'String'
    [void][IO.Directory]::CreateDirectory((Join-Path $profile 'OneDriveNotes'))
    Check (((Get-FixtureReport '').Folders | Where-Object Folder -eq 'Documents').UserClass -eq 'Custom') 'A folder named OneDriveNotes is not treated as OneDrive backup'
    Set-RegValue $userKey 'Desktop' '%USERPROFILE%\Desktop' 'ExpandString'
    $expanded=Get-SuiteOneDriveReport -UserShellKey $userKey -ShellKey $shellKey -PolicyKey $policyKey -ProfilePath $env:USERPROFILE -OneDriveRoots @() -OneDriveExecutable ''
    Check ((@($expanded.Folders) | Where-Object Folder -eq 'Desktop').UserClass -eq 'Local') 'The %USERPROFILE% Desktop value is the local default'

    $cloudRoot=Join-Path $profile 'OneDrive\Desktop'
    [void][IO.Directory]::CreateDirectory($cloudRoot)
    1..3 | ForEach-Object { [IO.File]::WriteAllText((Join-Path $cloudRoot "file$_.txt"),'x') }
    $offline=Join-Path $cloudRoot 'file1.txt'
    $item=Get-Item -LiteralPath $offline
    $item.Attributes=$item.Attributes -bor [IO.FileAttributes]::Offline
    Set-AllLocal
    Set-RegValue $userKey 'Desktop' $cloudRoot 'String'
    $scan=Get-FixtureReport '' -CountCloudOnly -CloudLimit 2
    $desktop=@($scan.Folders | Where-Object Folder -eq 'Desktop')
    Check ($desktop.UserClass -eq 'OneDrive' -and $desktop.Note -match 'file limit') 'Cloud scan is capped and does not treat the offline attribute as online-only'
    Check (Test-SuiteCloudOnlyAttribute 0x400000) 'Recall-on-data-access is online-only'
    Check (Test-SuiteCloudOnlyAttribute 0x40000) 'Recall-on-open is online-only'
    Check (-not (Test-SuiteCloudOnlyAttribute 0x1000)) 'The offline attribute alone is not enough'
    Check (-not (Test-SuiteOneDrivePath 'D:\Docs' @())) 'A custom drive path is not an OneDrive root'
    Check (Test-SuiteOneDrivePath 'D:\Cloud\Docs' @('D:\Cloud')) 'An account folder root counts even without the OneDrive name'

    # Invalid paths and optional modern aliases cannot bypass the local-folder gate.
    Set-AllLocal
    foreach ($bad in @('Documents','%TOOLKIT_UNDEFINED_ROOT%\Documents',(Join-Path $profile 'missing'), 'C:\broken|path', '\\server\share\Documents')) {
        Set-RegValue $userKey 'Personal' $bad 'String'
        $uncertain=Get-FixtureReport (Join-Path $fixture 'OneDrive.exe')
        Check (-not $uncertain.PolicyAllowed -and -not $uncertain.UninstallAllowed) "Unverified location blocks lock and uninstall: $bad"
    }
    Set-AllLocal
    Set-RegValue $userKey 'Personal' '123' 'DWord'
    Check (-not (Get-FixtureReport '').PolicyAllowed) 'A non-string known-folder registry value is unknown'
    Set-AllLocal
    Set-RegValue $shellKey 'Personal' 'Documents' 'String'
    $badCache=Get-FixtureReport ''
    Check (-not $badCache.PolicyAllowed -and ($badCache.Folders | Where-Object Folder -eq 'Documents').Status -eq 'Explorer cache location not verified') 'An invalid Explorer cache cannot display a safe local status'
    Set-AllLocal
    foreach ($alias in @('{F42EE2D3-909F-4907-8871-4C22FC0BF756}','{0DDD015D-B06C-45D5-8C4C-F59713854639}','{A0C69A99-21C8-4671-8703-7934162FCF1D}','{35286A68-3C57-41A1-BBB1-0EAE73D76C95}')) {
        Set-RegValue $userKey $alias $documents 'String'
        Check (-not (Get-FixtureReport '').PolicyAllowed) 'A modern local-folder alias still in OneDrive blocks the gate'
        Remove-ItemProperty -LiteralPath $userKey -Name $alias
    }
    Set-RegValue $shellKey '{F42EE2D3-909F-4907-8871-4C22FC0BF756}' $documents 'String'
    Check (-not (Get-FixtureReport '').PolicyAllowed) 'Modern shell-cache aliases are also checked before calling folders local'
    Remove-ItemProperty -LiteralPath $shellKey -Name '{F42EE2D3-909F-4907-8871-4C22FC0BF756}'

    # User-mode cannot set kernel recall flags. Feed metadata at the filesystem boundary,
    # and assert enumeration never follows virtual/linked directories or reads file data.
    $metadata=& (Get-Module Toolkit.Core) {
        try {
            $script:ScanRootAttributes=16
            $script:ScanEntries=@(
                [pscustomobject]@{FullName='X:\scan\cloud.txt';PSIsContainer=$false;Attributes=(0x400000 -bor 0x400)},
                [pscustomobject]@{FullName='X:\scan\virtual';PSIsContainer=$true;Attributes=(0x400000 -bor 0x400 -bor 16)},
                [pscustomobject]@{FullName='X:\scan\link';PSIsContainer=$true;Attributes=(0x400 -bor 16)})
            function Test-Path { $true }
            function Get-Item { [pscustomobject]@{Attributes=$script:ScanRootAttributes;PSIsContainer=$true} }
            function Get-ChildItem { param($LiteralPath) if ($LiteralPath -ne 'X:\scan') { throw 'Followed a virtual directory' }; $script:ScanEntries }
            $files=Get-SuiteCloudOnlyCount 'X:\scan'
            $script:ScanRootAttributes=0x400 -bor 16
            $linkedRoot=Get-SuiteCloudOnlyCount 'X:\scan'
            $script:ScanRootAttributes=16
            $script:ScanEntries=@(1..4 | ForEach-Object { [pscustomobject]@{FullName="X:\scan\dir$_";PSIsContainer=$true;Attributes=16} })
            $bounded=Get-SuiteCloudOnlyCount 'X:\scan' -Limit 2
            function Get-ChildItem { throw 'Injected enumeration denied' }
            $denied=Get-SuiteCloudOnlyCount 'X:\scan'
            [pscustomobject]@{Files=$files;LinkedRoot=$linkedRoot;Bounded=$bounded;Denied=$denied}
        } finally { Remove-Item Function:Test-Path,Function:Get-Item,Function:Get-ChildItem }
    }
    Check ($metadata.Files.Count -eq 1 -and $metadata.Files.Incomplete) 'Recall files are counted before reparse filtering; skipped directories make the count incomplete'
    Check ($metadata.LinkedRoot.Incomplete) 'A skipped linked or cloud root cannot report a complete zero'
    Check ($metadata.Bounded.Capped) 'Directory entries count toward the scan limit'
    Check ($metadata.Denied.Incomplete) 'Enumeration failure cannot report a complete zero'

    $live=Get-SuiteOneDriveReport
    Check ($live.Summary -is [string] -and $live.Folders.Count -eq 5) 'Live read-only report returns five folders and does not require a write'
    Write-Host "PASS: $checks OneDrive gate checks."
} finally {
    if ($testKey.StartsWith('HKCU:\Software\WindowsPCToolkitTests\') -and (Test-Path -LiteralPath $testKey)) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    if ([IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
