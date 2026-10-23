# OneDrive folder gate. Proves the toolkit refuses the lock and the location
# restore while backup is still on, and that a restore does not delete files.
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
    Check ($personal.RestoreAllowed -and -not $personal.UninstallAllowed) 'Gone app plus an OneDrive path is the restore case, not the uninstall case'
    $restored=Invoke-SuiteOneDriveFolderRestore -UserShellKey $userKey -ShellKey $shellKey -PolicyKey $policyKey -ProfilePath $profile -OneDriveRoots @() -OneDriveExecutable ''
    Check ($restored.Mode -eq 'OneDriveFolders' -and $restored.Status -eq 'Completed') 'Restore records a completed OneDriveFolders report'
    $afterUser=Get-RegValue $userKey 'Personal'
    Check ($afterUser.Kind -eq 'ExpandString' -and $afterUser.Value -eq (Join-Path $profile 'Documents')) 'Documents user location is the local profile path'
    Check ((Get-RegValue $shellKey 'Personal').Value -eq (Join-Path $profile 'Documents')) 'Documents Explorer cache matches the local path'
    Check ((Get-RegValue $userKey 'Desktop').Value -eq (Join-Path $profile 'Desktop')) 'A folder that was already local is not rewritten'
    Check ((Get-Content -LiteralPath $kept -Raw) -eq 'still here') 'Restore does not delete the file that was left in OneDrive'
    $undoFailed=$false
    try { Invoke-SuiteUndo -Path $restored.Path } catch { $undoFailed=$true; Check ($_.Exception.Message -match 'not put back') 'Undo explains that the OneDrive path is not restored' }
    Check $undoFailed 'Folder restore is not undone back onto the OneDrive path'
    Check ((Get-RegValue $userKey 'Personal').Value -eq (Join-Path $profile 'Documents')) 'Refused undo keeps the local Documents path'

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

    $live=Get-SuiteOneDriveReport
    Check ($live.Summary -is [string] -and $live.Folders.Count -eq 5) 'Live read-only report returns five folders and does not require a write'
    Write-Host "PASS: $checks OneDrive gate checks."
} finally {
    if ($testKey.StartsWith('HKCU:\Software\WindowsPCToolkitTests\') -and (Test-Path -LiteralPath $testKey)) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    if ([IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
