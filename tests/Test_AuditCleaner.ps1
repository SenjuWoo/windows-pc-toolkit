#requires -version 5.1
param([string]$CleanerPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if (-not $CleanerPath) {
    $CleanerPath=Join-Path $root 'pc-cleaner\PC_Cleaner.ps1'
    if (-not (Test-Path -LiteralPath $CleanerPath)) { $CleanerPath=Join-Path $root 'Pc Cleaner\PC_Cleaner.ps1' }
}
$fixture=Join-Path $env:TEMP ('Toolkit_CleanerAudit_'+[guid]::NewGuid().ToString('N'))
$key='HKCU:\Software\WindowsPCToolkitTests\Cleaner_'+[guid]::NewGuid().ToString('N')
$checks=0
function Check([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "TEST FAILED: $Message" }; $script:checks++ }
function Write-OldFile([string]$Path) {
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    [IO.File]::WriteAllText($Path,'owned fixture')
    [IO.File]::SetLastWriteTime($Path,(Get-Date).AddDays(-10))
    [IO.File]::SetLastAccessTime($Path,(Get-Date).AddDays(-10))
}
[void][IO.Directory]::CreateDirectory($fixture)
$links=New-Object Collections.ArrayList
try {
    . $CleanerPath -Action Library
    $denied=$false
    try { . $CleanerPath -Action Library -ExpectedUserSid 'S-1-5-21-0-0-0-999999' } catch { $denied=$true }
    Check $denied 'Cleaner refuses a different Windows identity before any bootstrap or action'
    . $CleanerPath -Action Library -ExpectedUserSid ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    Check $true 'Own Windows identity can load the cleaner without side effects'
    Check ((Get-CommandTargetPath '"C:\App Dir\app.exe" --startup') -eq 'C:\App Dir\app.exe') 'Quoted executable path is parsed exactly'
    Check ($null -eq (Get-CommandTargetPath 'C:\App Dir\app.exe --startup')) 'Ambiguous unquoted path with spaces is retained for review'
    Check ($null -eq (Get-CommandTargetPath 'C:\Dir.exe name\app.exe')) 'Executable-looking directory prefix does not become a false dead target'
    Check ((Get-CommandTargetPath 'C:\Apps\app.exe --startup') -eq 'C:\Apps\app.exe') 'Unambiguous executable with arguments remains supported'
    $brackets=Join-Path $fixture "Cache [1] ' literal"
    Write-OldFile (Join-Path $brackets 'Default\Cache\old.tmp')
    $pattern=[pscustomobject]@{Paths=@((Join-Path $brackets '*\Cache'))}
    Check (@(Resolve-CategoryDirs $pattern).Count -eq 1) 'Wildcard categories preserve literal brackets and apostrophes in parent paths'
    $pattern.Paths=@((Join-Path $brackets 'Default\Cache\*.tmp'))
    Check (@(Resolve-CategoryFiles $pattern).Count -eq 1) 'Wildcard file categories preserve literal brackets and apostrophes'
    $cats=@(Get-CleanCategories)
    foreach ($id in @('WindowsOld','BakFiles','WUCache','RecallData','AiAppCaches')) {
        $category=$cats | Where-Object Id -eq $id
        Check ($category.Profile -eq 'Report') "$id is excluded from both deleting profiles"
        # Even a caller with a stale Strict category cannot revive removed deletion code.
        $category.Profile='Strict'; $category.Kind='Special'
        $result=Invoke-CleanCategory $category
        Check ($result.Status -eq 'Skipped' -and $result.Removed -eq 0) "$id executor refuses a stale destructive category"
    }
    $tempRoot=Join-Path $fixture 'Temp'
    $outside=Join-Path $fixture 'Outside'
    Write-OldFile (Join-Path $tempRoot 'old.tmp')
    Write-OldFile (Join-Path $tempRoot 'new.tmp')
    [IO.File]::SetLastWriteTime((Join-Path $tempRoot 'new.tmp'),(Get-Date))
    Write-OldFile (Join-Path $tempRoot 'accessed.tmp')
    [IO.File]::SetLastAccessTime((Join-Path $tempRoot 'accessed.tmp'),(Get-Date))
    Write-OldFile (Join-Path $tempRoot 'Documents\keep.tmp')
    Write-OldFile (Join-Path $tempRoot '.ollama\models\keep.tmp')
    Write-OldFile (Join-Path $outside 'Cache\keep.tmp')
    $link=Join-Path $fixture 'linked'
    New-Item -ItemType Junction -Path $link -Value $outside | Out-Null
    [void]$links.Add($link)
    $nested=Join-Path $tempRoot 'nested-link'
    New-Item -ItemType Junction -Path $nested -Value $outside | Out-Null
    [void]$links.Add($nested)
    Check (-not (Test-CleanPathWithoutLinks (Join-Path $link 'Cache\keep.tmp'))) 'Ancestor junction is refused, even when leaf is a normal file'
    Check (-not (Remove-ItemSafe (Join-Path $link 'Cache\keep.tmp'))) 'Direct file deletion through an ancestor junction is refused'
    Check (-not (Remove-ItemSafe (Join-Path $link 'Cache') -Directory)) 'Recursive directory deletion through an ancestor junction is refused'
    Check (@(Get-DisposableTempFiles @((Join-Path $link 'Cache'))).Count -eq 0) 'Temp root below a junction yields no candidates'
    $category=[pscustomobject]@{Id='EdgeCaches';Label='Fixture';Profile='Balanced';Kind='Children';Paths=@((Join-Path $link 'Cache'))}
    $result=Invoke-CleanCategory $category
    Check ($result.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $outside 'Cache\keep.tmp'))) 'Category cache root below a junction preserves destination files'
    $category=[pscustomobject]@{Id='UserTemp';Label='Fixture';Profile='Balanced';Kind='Children';Paths=@($tempRoot)}
    $measurement=Measure-Category $category
    Check ($measurement.Files -eq 1) 'Temp scan counts only aged, unaccessed, unprotected files and skips junctions'
    # Enumeration may update access time; reset only the one owned candidate.
    [IO.File]::SetLastAccessTime((Join-Path $tempRoot 'old.tmp'),(Get-Date).AddDays(-10))
    $result=Invoke-CleanCategory $category
    Check ($result.Removed -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $tempRoot 'old.tmp'))) 'Aged disposable file is actually deleted'
    foreach ($path in @('new.tmp','accessed.tmp','Documents\keep.tmp','.ollama\models\keep.tmp')) { Check (Test-Path -LiteralPath (Join-Path $tempRoot $path)) "Protected/recent $path survives" }
    $locked=Join-Path $tempRoot 'locked.tmp'
    Write-OldFile $locked
    $stream=[IO.File]::Open($locked,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { Check (-not (Remove-ItemSafe $locked)) 'Locked file removal returns a skip, preserving bytes' } finally { $stream.Dispose() }
    Check (Test-Path -LiteralPath $locked) 'Locked file remains after failed removal'
    Check (-not (Remove-ItemSafe $tempRoot -Directory)) 'Recursive deletion containing protected names or links is refused'
    $savedTemp=(Get-Item Function:Get-DisposableTempFiles).ScriptBlock
    function Get-DisposableTempFiles { param($Roots) [IO.File]::SetLastWriteTime($locked,(Get-Date)); Get-Item -LiteralPath $locked }
    $result=Invoke-CleanCategory $category
    Check ($result.Removed -eq 0 -and (Test-Path -LiteralPath $locked)) 'Temp cleanup rechecks file age after enumeration'
    Set-Item Function:Get-DisposableTempFiles $savedTemp

    $shown=New-Object Collections.ArrayList
    function Show-ScanLine { param($Category,$Info,$Prefix) [void]$shown.Add($Category.Id) }
    function Measure-Category { param($Category) [pscustomobject]@{Files=1;Bytes=[long]1} }
    $null=Show-ScanReport
    foreach ($id in @('WindowsOld','BakFiles','WUCache','RecallData','AiAppCaches','ModelStores')) { Check ($shown -contains $id) "Scan renders the kept $id category" }
    Remove-Item Function:Show-ScanLine,Function:Measure-Category

    # Official cmdlet is faked: never clean the real Windows delivery cache.
    function Measure-Category { param($Category) [pscustomobject]@{Files=5;Bytes=[long]1234} }
    function Delete-DeliveryOptimizationCache { param([switch]$Force) }
    $result=Invoke-CleanCategory ([pscustomobject]@{Id='DeliveryOptimization';Label='Fixture';Profile='Balanced';Kind='Special';Paths=@()})
    Check ($result.Removed -eq 0 -and $result.Bytes -eq 0) 'No-op Windows cache cleanup does not claim every pre-existing file was deleted'
    function Delete-DeliveryOptimizationCache { param([switch]$Force) throw 'injected permission failure' }
    $result=Invoke-CleanCategory ([pscustomobject]@{Id='DeliveryOptimization';Label='Fixture';Profile='Balanced';Kind='Special';Paths=@()})
    Check ($result.Status -eq 'Failed' -and $result.Note -match 'injected permission failure') 'Cache command failure remains a failure in the result'
    Remove-Item Function:Measure-Category,Function:Delete-DeliveryOptimizationCache

    # One real typed journal against an owned HKCU key; no real startup key is touched.
    Import-Module (Join-Path $root 'Modules\Toolkit.Core.psm1') -ArgumentList (Join-Path $fixture 'State') -Force -DisableNameChecking
    & (Get-Module Toolkit.Core) { function script:Assert-Administrator { } }
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -LiteralPath $key -Name 'Fixture' -Value ('"'+(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')+'"') -PropertyType String | Out-Null
    function Assert-Admin { }
    function Import-Module { }
    function Read-Host { param($Prompt) 'A' }
    function Get-RegistryIssues { [pscustomobject]@{Category='Dead startup entries';Kind='Value';Key=$key;Name='Fixture';Display=($fixture+'\missing.exe');Evidence='old scan'} }
    Invoke-RegistryCare
    Check ((Get-Item -LiteralPath $key).GetValueNames() -contains 'Fixture') 'Registry care rechecks current startup command and preserves a newly valid target'
    Set-ItemProperty -LiteralPath $key -Name 'Fixture' -Value ('"'+$fixture+'\missing.exe"')
    Invoke-RegistryCare
    Check ((Get-Item -LiteralPath $key).GetValueNames() -notcontains 'Fixture') 'Registry care removes only the currently verified missing target'
    $history=Get-SuiteHistory | Where-Object Mode -eq 'RegistryCare' | Select-Object -First 1
    $undo=Invoke-SuiteUndo $history.Path
    Check ($undo.Status -eq 'Restored' -and (Get-ItemPropertyValue -LiteralPath $key -Name 'Fixture') -eq ('"'+$fixture+'\missing.exe"')) 'Cleaner registry journal undo restores exact original value'
    $suite=Get-Module Toolkit.Core
    function Set-SuiteRegistry {
        param($Run,$Path,$Name,$Value,[switch]$Remove)
        & $suite { param($Run,$Path,$Name,$Value) Set-SuiteRegistry $Run $Path $Name $Value -Remove } $Run $Path $Name $Value
        throw 'injected interruption after removal'
    }
    Invoke-RegistryCare
    Check ((Get-ItemPropertyValue -LiteralPath $key -Name 'Fixture') -eq ('"'+$fixture+'\missing.exe"')) 'Failed individual registry repair rolls back its partial removal'
    $failed=Get-SuiteHistory | Where-Object Mode -eq 'RegistryCare' | Select-Object -First 1
    Check ($failed.Status -eq 'CompletedWithErrors') 'Partial registry repair failure remains visible after rollback'
    Remove-Item Function:Set-SuiteRegistry
    # Legacy file backup restore must not overwrite a replacement made by the user.
    $RegBackupRoot=Join-Path $fixture 'Legacy'
    $legacy=Join-Path $RegBackupRoot '20200101'
    [void][IO.Directory]::CreateDirectory($legacy)
    $existing=Join-Path $fixture 'replacement.lnk'; $backup=Join-Path $legacy 'original.lnk'
    [IO.File]::WriteAllText($existing,'new user shortcut'); [IO.File]::WriteAllText($backup,'old shortcut')
    [pscustomobject]@{Items=@([pscustomobject]@{Type='File';Path=$existing;Backup=$backup})} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $legacy 'manifest.json') -Encoding UTF8
    function Get-SuiteHistory { }
    Restore-LatestRegistryBackup
    Check ([IO.File]::ReadAllText($existing) -eq 'new user shortcut') 'Legacy file restore preserves an existing replacement'
    Remove-Item Function:Get-SuiteHistory
    function Read-Host { param($Prompt) '1-2147483647' }
    Invoke-PickCategories
    Check $true 'Unbounded category range is rejected without allocation or deletion'
    foreach ($name in @('Assert-Admin','Import-Module','Read-Host','Get-RegistryIssues')) { Remove-Item ('Function:'+$name) }
    # Restore cleaner helpers after scope-local fakes and module imports.
    . $CleanerPath -Action Library
    $StateRoot=Join-Path $fixture 'CleanerState'; $LogRoot=Join-Path $StateRoot 'Logs'; $RegBackupRoot=Join-Path $StateRoot 'RegistryBackups'; $FileBackupRoot=Join-Path $StateRoot 'FileBackups'
    $sample=[pscustomobject]@{Bytes=0;Status='Failed'}
    $first=Save-RunLog 'Fixture' @($sample) 0 0
    $second=Save-RunLog 'Fixture' @($sample) 0 0
    Check ($first -ne $second -and (Test-Path -LiteralPath $first) -and (Test-Path -LiteralPath $second)) 'Runs in the same second retain separate logs'
    Check ((Get-Content -LiteralPath $first -Raw | ConvertFrom-Json).Status -eq 'CompletedWithErrors') 'Persisted clean log reports category failure'
    $savedLocal=$env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA=Join-Path $fixture 'Local'
        Write-CleanerDiagnostic 'Fixture' 'quiet'
        Check (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'WindowsPCToolkit\Logs\Cleaner_debug.log'))) 'Library import stays quiet with no debug files'
        $script:CleanerDebugEnabled=$true
        Write-CleanerDiagnostic 'Startup' "Action=Fixture; StateRoot=$StateRoot"
        $debug=Join-Path $env:LOCALAPPDATA 'WindowsPCToolkit\Logs\Cleaner_debug.log'
        Check ((Get-Content -LiteralPath $debug -Raw) -match 'v1\.1\.1 Startup: Action=Fixture; StateRoot=') 'Enabled diagnostic records version and resolved configuration'
        [IO.File]::WriteAllBytes($debug,(New-Object byte[] 1048576))
        Write-CleanerDiagnostic 'Failure' 'fixture cause'
        Check ((Test-Path -LiteralPath ($debug+'.1')) -and (Get-Item -LiteralPath $debug).Length -lt 1MB) 'Diagnostic output rotates at one MiB'
    } finally { $env:LOCALAPPDATA=$savedLocal }
    Write-Host "PASS: $checks cleaner audit regression checks"
} finally {
    foreach ($link in $links) { if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) } }
    if ($stream) { $stream.Dispose() }
    Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
    if ([IO.Path]::GetFileName($fixture) -like 'Toolkit_CleanerAudit_*') { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
}
