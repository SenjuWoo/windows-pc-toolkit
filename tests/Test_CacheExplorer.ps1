# Cache Explorer regression suite. Every check runs against disposable TEMP fixtures;
# no real cache, game, project or user folder is read or changed.
#requires -version 5.1
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$checks = 0
function Check([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "TEST FAILED: $Message" }; $script:checks++ }

$root = $Root
$fixture = Join-Path $env:TEMP ('ToolkitCache_' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
try {
    $cleaner = Join-Path $root 'pc-cleaner\PC_Cleaner.ps1'
    if (-not (Test-Path -LiteralPath $cleaner)) { $cleaner = Join-Path $root 'Pc Cleaner\PC_Cleaner.ps1' }
    . $cleaner -Action Library
    $StateRoot = Join-Path $fixture 'State'
    $LogRoot = Join-Path $fixture 'Logs'
    $RegBackupRoot = Join-Path $fixture 'RegBackup'
    $FileBackupRoot = Join-Path $fixture 'FileBackup'
    [void][IO.Directory]::CreateDirectory($StateRoot)

    function New-Entry([string]$Id, [string[]]$Paths, [string]$Kind = 'Children', [int]$AgeDays = 0, [string]$Risk = 'SAFE', [bool]$Delete = $true) {
        [pscustomobject]@{ Id = $Id; Section = 'Dev'; Label = $Id; Risk = $Risk; Delete = $Delete; Kind = $Kind; AgeDays = $AgeDays; RequireProcess = $null; Signature = $null; Paths = $Paths; Impact = 'fixture'; Source = 'fixture' }
    }

    # 1. A verified cache removes only its own contents.
    $safe = Join-Path $fixture 'safe\Cache'
    [void][IO.Directory]::CreateDirectory($safe)
    'a' | Set-Content -LiteralPath (Join-Path $safe 'a.tmp')
    'b' | Set-Content -LiteralPath (Join-Path $safe 'b.tmp')
    'keep' | Set-Content -LiteralPath (Join-Path $fixture 'safe\settings.json')
    $r = Invoke-CacheClean -Entry (New-Entry 'SafeCache' @($safe))
    Check ($r.Status -eq 'Completed' -and $r.Removed -eq 2) 'A verified cache removes exactly its own files'
    Check (@(Get-ChildItem -LiteralPath $safe -Force).Count -eq 0) 'Cache contents are gone'
    Check (Test-Path -LiteralPath (Join-Path $fixture 'safe\settings.json')) 'A sibling settings file is untouched'

    # 2. A protected folder nested inside a cache refuses the whole directory (fail closed).
    $mixed = Join-Path $fixture 'mixed\Cache'
    [void][IO.Directory]::CreateDirectory((Join-Path $mixed 'Documents'))
    'user' | Set-Content -LiteralPath (Join-Path $mixed 'Documents\note.txt')
    'junk' | Set-Content -LiteralPath (Join-Path $mixed 'junk.tmp')
    $r = Invoke-CacheClean -Entry (New-Entry 'MixedCache' @($mixed))
    Check ($r.Removed -eq 0) 'A cache containing a protected folder is refused entirely'
    Check ((Test-Path -LiteralPath (Join-Path $mixed 'Documents\note.txt')) -and (Test-Path -LiteralPath (Join-Path $mixed 'junk.tmp'))) 'Nothing was removed from the refused cache'

    # 3. A junction in the path stops both measurement and deletion.
    $real = Join-Path $fixture 'realcache'
    [void][IO.Directory]::CreateDirectory($real)
    'x' | Set-Content -LiteralPath (Join-Path $real 'x.tmp')
    $link = Join-Path $fixture 'linked'
    New-Item -ItemType Junction -Path $link -Target $real -ErrorAction Stop | Out-Null
    $entry = New-Entry 'LinkedCache' @($link)
    $measure = Get-CacheEntryMeasure -Entry $entry
    Check (-not $measure.Present -and $measure.Files -eq 0) 'A junction path is not measured'
    $r = Invoke-CacheClean -Entry $entry
    Check ($r.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $real 'x.tmp'))) 'A junction path is never deleted through'

    # 4. A locked file is skipped and counted, not forced.
    $locked = Join-Path $fixture 'locked\Cache'
    [void][IO.Directory]::CreateDirectory($locked)
    'free' | Set-Content -LiteralPath (Join-Path $locked 'free.tmp')
    'busy' | Set-Content -LiteralPath (Join-Path $locked 'busy.tmp')
    $stream = [IO.File]::Open((Join-Path $locked 'busy.tmp'), 'Open', 'Read', 'None')
    try {
        $r = Invoke-CacheClean -Entry (New-Entry 'LockedCache' @($locked))
        Check ($r.Removed -eq 1 -and $r.Skipped -ge 1) 'A locked file is skipped and reported'
        Check (Test-Path -LiteralPath (Join-Path $locked 'busy.tmp')) 'The locked file still exists'
    } finally { $stream.Dispose() }

    # 5. Profile names with brackets and apostrophes are handled literally.
    $odd = Join-Path $fixture "O'Brien [test]\Cache"
    [void][IO.Directory]::CreateDirectory($odd)
    'z' | Set-Content -LiteralPath (Join-Path $odd 'z.tmp')
    $r = Invoke-CacheClean -Entry (New-Entry 'OddPath' @($odd))
    Check ($r.Removed -eq 1) 'A path with brackets and an apostrophe cleans normally'

    # 6. Missing or invalid environment variables are inert.
    $r = Invoke-CacheClean -Entry (New-Entry 'MissingRoot' @('%WINDOWS_PC_TOOLKIT_NO_SUCH_ROOT%\cache'))
    Check ($r.Removed -eq 0 -and $r.Skipped -eq 0) 'A missing environment root does nothing'
    $measure = Get-CacheEntryMeasure -Entry (New-Entry 'Empty' @(''))
    Check (-not $measure.Present) 'An empty path is not present'

    # 7. Report-only catalog entries refuse deletion even when files exist.
    $scratch = Join-Path $fixture 'hermes\cache\scratch'
    [void][IO.Directory]::CreateDirectory($scratch)
    'old' | Set-Content -LiteralPath (Join-Path $scratch 'old.tmp')
    $readOnly = New-Entry 'HermesScratch' @($scratch) -Delete $false
    $r = Invoke-CacheClean -Entry $readOnly
    Check ($r.Status -eq 'Skipped' -and (Test-Path -LiteralPath (Join-Path $scratch 'old.tmp'))) 'Report-only entries never delete'

    # 8. Session/config names are protected even inside a cache-shaped folder.
    foreach ($name in @('sessions', 'globalStorage', 'state.db', '.claude', 'mods')) {
        $probe = Join-Path $fixture ('probe_' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory((Join-Path $probe $name))
        'keep' | Set-Content -LiteralPath (Join-Path $probe "$name\keep.txt")
        $r = Invoke-CacheClean -Entry (New-Entry ('Guard_' + $name) @($probe))
        Check ($r.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $probe "$name\keep.txt"))) ("'{0}' is protected inside a disposable folder" -f $name)
    }

    # 9. A helper folder next to a cache is untouched (VRChat config/screenshots shape).
    $vr = Join-Path $fixture 'VRChat\VRChat'
    [void][IO.Directory]::CreateDirectory((Join-Path $vr 'Cache-WindowsPlayer'))
    [void][IO.Directory]::CreateDirectory((Join-Path $vr 'Screenshots'))
    'cfg' | Set-Content -LiteralPath (Join-Path $vr 'config.json')
    'avatar' | Set-Content -LiteralPath (Join-Path $vr 'Cache-WindowsPlayer\avatar.bin')
    # The row carries the config it was scanned with; a clean may only be judged by that config.
    $vrCfg = Join-Path $vr 'config.json'
    @{ cache_directory = (Join-Path $vr 'Cache-WindowsPlayer') } | ConvertTo-Json -Compress | Set-Content -LiteralPath $vrCfg -Encoding UTF8
    $vrLive = New-Entry 'VRChatCache' @((Join-Path $vr 'Cache-WindowsPlayer'))
    $vrLive | Add-Member -NotePropertyName ConfigPath -NotePropertyValue $vrCfg -Force
    $r = Invoke-CacheClean -Entry $vrLive
    Check ($r.Removed -eq 1 -and (Test-Path -LiteralPath (Join-Path $vr 'config.json')) -and (Test-Path -LiteralPath (Join-Path $vr 'Screenshots'))) 'A VRChat cache clean keeps config and screenshots'

    # 10. Steam shadercache is separate from installed games.
    $steamApps = Join-Path $fixture 'Steam\steamapps'
    [void][IO.Directory]::CreateDirectory((Join-Path $steamApps 'shadercache'))
    [void][IO.Directory]::CreateDirectory((Join-Path $steamApps 'common\Game'))
    'shader' | Set-Content -LiteralPath (Join-Path $steamApps 'shadercache\s.bin')
    'exe' | Set-Content -LiteralPath (Join-Path $steamApps 'common\Game\game.exe')
    $r = Invoke-CacheClean -Entry (New-Entry 'SteamShaderCache' @((Join-Path $steamApps 'shadercache')) -Risk 'STRICT')
    Check ($r.Removed -eq 1 -and (Test-Path -LiteralPath (Join-Path $steamApps 'common\Game\game.exe'))) 'Shader cleanup never reaches steamapps\common'

    # 11. Catalog paths stay inside their documented folder and never name game data.
    $catalog = @(Get-CacheCatalog)
    $steamEntry = $catalog | Where-Object Id -eq 'SteamShaderCache'
    Check (@($steamEntry.Paths | Where-Object { $_ -match '\\common|compatdata|appmanifest' }).Count -eq 0) 'No Steam catalog path points at games or manifests'
    Check (@($catalog | Where-Object { $_.Id -match 'Codex|Claude|Hermes' -and $_.Delete }).Count -eq 0) 'AI home folders are report-only'

    # 12. A folder renamed to a protected name between scan and delete is refused.
    $flip = Join-Path $fixture 'flip\Cache'
    [void][IO.Directory]::CreateDirectory($flip)
    'data' | Set-Content -LiteralPath (Join-Path $flip 'd.tmp')
    $entry = New-Entry 'FlipCache' @($flip)
    $scan = @(Get-CacheScan -Catalog @($entry))
    Check ($scan[0].Present) 'The fixture cache is visible at scan time'
    Rename-Item -LiteralPath $flip -NewName 'Documents'
    $r = Invoke-CacheClean -Entry $entry
    Check ($r.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $fixture 'flip\Documents\d.tmp'))) 'A path that became protected after the scan is refused'

    # 13. Repeated cleanup is idempotent.
    $again = Join-Path $fixture 'again\Cache'
    [void][IO.Directory]::CreateDirectory($again)
    'one' | Set-Content -LiteralPath (Join-Path $again 'one.tmp')
    $e = New-Entry 'AgainCache' @($again)
    $first = Invoke-CacheClean -Entry $e
    $second = Invoke-CacheClean -Entry $e
    Check ($first.Removed -eq 1 -and $second.Removed -eq 0 -and $second.Bytes -eq 0) 'A repeated clean removes nothing and reports zero bytes'

    # 14. Overlapping categories cannot double count: the second one finds nothing.
    $shared = Join-Path $fixture 'shared\Cache'
    [void][IO.Directory]::CreateDirectory($shared)
    's' | Set-Content -LiteralPath (Join-Path $shared 's.tmp')
    $a = Invoke-CacheClean -Entry (New-Entry 'OverlapA' @($shared))
    $b = Invoke-CacheClean -Entry (New-Entry 'OverlapB' @($shared))
    Check ($a.Removed -eq 1 -and $b.Removed -eq 0) 'Overlapping categories report disjoint bytes'

    # 15. A scan is read-only and the JSON report is written.
    $ro = Join-Path $fixture 'readonly\Cache'
    [void][IO.Directory]::CreateDirectory($ro)
    'f' | Set-Content -LiteralPath (Join-Path $ro 'f.tmp')
    $before = @(Get-ChildItem -LiteralPath $ro -Force).Count
    $scan = @(Get-CacheScan -Catalog @((New-Entry 'ReadOnly' @($ro))))
    Check ($scan[0].Files -eq 1 -and @(Get-ChildItem -LiteralPath $ro -Force).Count -eq $before) 'Scanning changes nothing'
    $json = Export-CacheScan -Scan $scan
    $parsed = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
    Check ($parsed.Items[0].Id -eq 'ReadOnly' -and $parsed.Version -eq $Script:Version) 'The exported report names the version and the category'

    # 16. A running app blocks its category.
    $busyRoot = Join-Path $fixture 'busyapp\Cache'
    [void][IO.Directory]::CreateDirectory($busyRoot)
    'x' | Set-Content -LiteralPath (Join-Path $busyRoot 'x.tmp')
    $running = New-Entry 'BusyApp' @($busyRoot)
    $running | Add-Member -NotePropertyName RequireProcess -NotePropertyValue 'powershell' -Force
    $r = Invoke-CacheClean -Entry $running
    Check ($r.Status -eq 'Skipped' -and (Test-Path -LiteralPath (Join-Path $busyRoot 'x.tmp'))) 'A running application blocks its cache cleanup'

    # 17. An unverified layout signature blocks deletion.
    $unsigned = Join-Path $fixture 'unsigned\Cache'
    [void][IO.Directory]::CreateDirectory($unsigned)
    'x' | Set-Content -LiteralPath (Join-Path $unsigned 'x.tmp')
    $signed = New-Entry 'SignedApp' @($unsigned)
    $signed | Add-Member -NotePropertyName Signature -NotePropertyValue (Join-Path $fixture 'unsigned\User') -Force
    $r = Invoke-CacheClean -Entry $signed
    Check ($r.Status -eq 'Skipped' -and (Test-Path -LiteralPath (Join-Path $unsigned 'x.tmp'))) 'An unproven layout is refused'

    # 18. A wildcard directory pattern is measured as directories, not as files.
    $epicRoot = Join-Path $fixture 'epic'
    $epicSaved = Join-Path $epicRoot 'Saved'
    $epicA = Join-Path $epicSaved 'webcache_4147'
    $epicB = Join-Path $epicSaved 'webcache_1511'
    [void][IO.Directory]::CreateDirectory($epicA)
    [void][IO.Directory]::CreateDirectory($epicB)
    'one' | Set-Content -LiteralPath (Join-Path $epicA 'a.dat')
    'twos' | Set-Content -LiteralPath (Join-Path $epicB 'b.dat')
    $epic = New-Entry 'EpicWebCache' @((Join-Path $epicSaved 'webcache_*'))
    $m = Get-CacheEntryMeasure -Entry $epic
    Check ($m.Files -eq 2 -and $m.Bytes -eq 11 -and $m.Paths.Count -eq 2) 'A wildcard directory pattern measures its directories'
    $r = Invoke-CacheClean -Entry $epic
    Check ($r.Removed -eq 2 -and $r.Bytes -eq 11) 'Cleanup removes exactly what the wildcard measurement found'
    Check (-not (Test-Path -LiteralPath (Join-Path $epicA 'a.dat'))) 'Wildcard directory contents are gone'

    # 19. The bounded enumerator stops at the cap instead of walking the whole tree.
    $big = Join-Path $fixture 'big\Cache'
    [void][IO.Directory]::CreateDirectory($big)
    1..20 | ForEach-Object { ('x' | Set-Content -LiteralPath (Join-Path $big ("f{0}.tmp" -f $_))) }
    $m = Get-CacheEntryMeasure -Entry (New-Entry 'BigCache' @($big)) -MaxFiles 5
    Check ($m.Capped -and $m.Files -eq 5) 'A small cap stops the scan early and is reported'

    # 20. An old tree with a fresh file keeps the fresh file, including nested.
    $aged = Join-Path $fixture 'aged\Cache'
    [void][IO.Directory]::CreateDirectory((Join-Path $aged 'nested'))
    'old' | Set-Content -LiteralPath (Join-Path $aged 'old.tmp')
    'old2' | Set-Content -LiteralPath (Join-Path $aged 'nested\old2.tmp')
    'new' | Set-Content -LiteralPath (Join-Path $aged 'nested\new.tmp')
    (Get-Item -LiteralPath (Join-Path $aged 'old.tmp')).LastWriteTime = (Get-Date).AddDays(-30)
    (Get-Item -LiteralPath (Join-Path $aged 'nested\old2.tmp')).LastWriteTime = (Get-Date).AddDays(-30)
    (Get-Item -LiteralPath $aged).LastWriteTime = (Get-Date).AddDays(-30)
    (Get-Item -LiteralPath (Join-Path $aged 'nested')).LastWriteTime = (Get-Date).AddDays(-30)
    $agedEntry = New-Entry 'AgedCache' @($aged) -AgeDays 7
    $m = Get-CacheEntryMeasure -Entry $agedEntry
    Check ($m.EligibleBytes -lt $m.Bytes) 'Eligible bytes exclude the fresh file'
    $r = Invoke-CacheClean -Entry $agedEntry
    Check ($r.Removed -eq 2 -and $r.Skipped -eq 1) 'Only aged files are removed from a mixed tree'
    Check (Test-Path -LiteralPath (Join-Path $aged 'nested\new.tmp')) 'A fresh file nested in an old directory survives'
    Check ($r.Bytes -eq $m.EligibleBytes) 'Removed bytes equal the scan eligible bytes'

    # 21. A file refreshed after the scan is kept by the age check at deletion time.
    $race = Join-Path $fixture 'race\Cache'
    [void][IO.Directory]::CreateDirectory($race)
    'r' | Set-Content -LiteralPath (Join-Path $race 'r.tmp')
    (Get-Item -LiteralPath (Join-Path $race 'r.tmp')).LastWriteTime = (Get-Date).AddDays(-30)
    $raceEntry = New-Entry 'RaceCache' @($race) -AgeDays 7
    $m = Get-CacheEntryMeasure -Entry $raceEntry
    Check ($m.EligibleBytes -gt 0) 'The aged file is eligible at scan time'
    (Get-Item -LiteralPath (Join-Path $race 'r.tmp')).LastWriteTime = Get-Date
    $r = Invoke-CacheClean -Entry $raceEntry
    Check ($r.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $race 'r.tmp'))) 'A file refreshed after the scan is kept'

    # 22. Two reports written in the same second get different names.
    $scan = @(Get-CacheScan -Catalog @((New-Entry 'ReportCache' @($race))))
    $one = Export-CacheScan -Scan $scan
    $two = Export-CacheScan -Scan $scan
    Check ($one -ne $two -and (Test-Path -LiteralPath $one) -and (Test-Path -LiteralPath $two)) 'Reports written together get unique names'

    # 23. The cleanup-root validator refuses broad or shared locations and accepts a real cache.
    $deep = Join-Path $fixture 'apps\SomeApp\Cache'
    [void][IO.Directory]::CreateDirectory($deep)
    Check ((Test-CleanupRoot -Path $deep).Ok) 'A dedicated cache folder is accepted as a cleanup root'
    foreach ($bad in @('C:\', $env:USERPROFILE, $env:LOCALAPPDATA, "$env:USERPROFILE\AppData\LocalLow", $env:SystemRoot, $env:ProgramFiles, (Join-Path $fixture 'apps\SomeApp'))) {
        $verdict = Test-CleanupRoot -Path $bad
        Check (-not $verdict.Ok) ("'{0}' is refused as a cleanup root ({1})" -f $bad, $verdict.Reason)
    }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if ($docs) { Check (-not (Test-CleanupRoot -Path $docs).Ok) 'The Documents folder is refused as a cleanup root' }

    # 24. A junction standing in for a cache root is refused, never followed.
    $realCache = Join-Path $fixture 'real\Cache'
    [void][IO.Directory]::CreateDirectory($realCache)
    $linkCache = Join-Path $fixture 'link\Cache'
    [void][IO.Directory]::CreateDirectory((Split-Path $linkCache -Parent))
    $made = $false
    try { cmd /c mklink /J "$linkCache" "$realCache" | Out-Null; $made = $true } catch { $made = $false }
    if ($made) {
        Check (-not (Test-CleanupRoot -Path $linkCache).Ok) 'A junction is refused as a cleanup root'
        'keep' | Set-Content -LiteralPath (Join-Path $realCache 'keep.tmp')
        $r = Invoke-CacheClean -Entry (New-Entry 'LinkCache' @($linkCache))
        Check ($r.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $realCache 'keep.tmp'))) 'Cleanup does not traverse a junction'
        [IO.Directory]::Delete($linkCache)
    }

    # 25. A category that changes its own configured location after the scan is refused.
    $cfg = Join-Path $fixture 'vrchat\config.json'
    [void][IO.Directory]::CreateDirectory((Split-Path $cfg -Parent))
    $cacheA = Join-Path $fixture 'vr\CacheA'
    $cacheB = Join-Path $fixture 'vr\CacheB'
    [void][IO.Directory]::CreateDirectory($cacheA)
    [void][IO.Directory]::CreateDirectory($cacheB)
    'a' | Set-Content -LiteralPath (Join-Path $cacheA 'a.bin')
    # ConvertTo-Json escapes separators itself; a hand-built string is host-dependent.
    @{ cache_directory = $cacheA } | ConvertTo-Json -Compress | Set-Content -LiteralPath $cfg -Encoding UTF8
    $readA = [IO.Path]::GetFullPath((Get-VRChatCachePath -ConfigPath $cfg))
    Check ([string]::Equals($readA.TrimEnd([char]92), [IO.Path]::GetFullPath($cacheA).TrimEnd([char]92), [StringComparison]::OrdinalIgnoreCase)) 'The configured cache_directory is read'
    @{ cache_directory = $cacheB } | ConvertTo-Json -Compress | Set-Content -LiteralPath $cfg -Encoding UTF8
    $readB = [IO.Path]::GetFullPath((Get-VRChatCachePath -ConfigPath $cfg))
    Check ([string]::Equals($readB.TrimEnd([char]92), [IO.Path]::GetFullPath($cacheB).TrimEnd([char]92), [StringComparison]::OrdinalIgnoreCase)) 'A changed cache_directory is re-read, not cached'

    # 26. An entry whose configured path is broad is refused at execution, not just at scan.
    $unsafe = [pscustomobject]@{ Id = 'VRChatCache'; Section = 'Gaming'; Label = 'VRChat cache'; Risk = 'CAREFUL'; Delete = $true
        AgeDays = 0; RequireProcess = $null; Signature = $null; RootPolicy = 'DedicatedCache'; Paths = @($env:USERPROFILE)
        Impact = 'fixture'; Source = 'fixture' }
    $r = Invoke-CacheClean -Entry $unsafe
    Check ($r.Status -eq 'Skipped' -and $r.Removed -eq 0) 'A profile root configured as a cache is refused at execution'
    $r = Invoke-CacheClean -Entry (New-Entry 'DriveRoot' @('C:\'))
    Check ($r.Status -eq 'Skipped' -and $r.Removed -eq 0) 'A drive root is never cleaned'

    # 27. Steam's own shadercache under Program Files is cleanable, everything else there is not.
    $lib = Join-Path $fixture 'steamlibrary'
    $shader = Join-Path $lib 'steamapps\shadercache'
    $common = Join-Path $lib 'steamapps\common\SomeGame'
    [void][IO.Directory]::CreateDirectory((Join-Path $shader '111'))
    [void][IO.Directory]::CreateDirectory($common)
    'shader' | Set-Content -LiteralPath (Join-Path $shader '111\shaders.bin')
    'game' | Set-Content -LiteralPath (Join-Path $common 'game.exe')

    Check ((Test-CleanupRoot -Path $shader -AllowAnyName -Policy SteamShader -SteamRoots @($lib)).Ok) 'A verified Steam shadercache is accepted under the Steam policy'
    # With a real Steam install under Program Files, the generic policy must still refuse it.
    $pfShader = Join-Path $env:ProgramFiles 'Steam\steamapps\shadercache'
    if (Test-Path -LiteralPath $pfShader -PathType Container) {
        Check (-not (Test-CleanupRoot -Path $pfShader -AllowAnyName).Ok) 'The real Program Files shadercache is refused by the generic policy'
        Check ((Test-CleanupRoot -Path $pfShader -AllowAnyName -Policy SteamShader).Ok) 'The same folder passes the Steam policy'
    }
    Check (-not (Test-CleanupRoot -Path $common -AllowAnyName -Policy SteamShader -SteamRoots @($lib)).Ok) 'steamapps\common is not a shader cache'
    Check (-not (Test-CleanupRoot -Path (Join-Path $lib 'steamapps') -AllowAnyName -Policy SteamShader -SteamRoots @($lib)).Ok) 'steamapps itself is not a shader cache'
    $forgedPf = Join-Path $env:ProgramFiles 'Cache'
    Check (-not (Test-CleanupRoot -Path $forgedPf -AllowAnyName -Policy SteamShader -SteamRoots @($lib)).Ok) 'An arbitrary Program Files folder is refused even under the Steam policy'
    Check (-not (Test-CleanupRoot -Path $shader -AllowAnyName -Policy SteamShader -SteamRoots @((Join-Path $fixture 'otherlib'))).Ok) 'A shadercache outside the reported libraries is refused'

    $steamEntry = New-Entry 'SteamShaderCache' @($shader)
    $steamEntry | Add-Member -NotePropertyName RootPolicy -NotePropertyValue 'SteamShader' -Force
    $steamEntry | Add-Member -NotePropertyName SteamRoots -NotePropertyValue @($lib) -Force
    $r = Invoke-CacheClean -Entry $steamEntry -SteamRoots @($lib)
    Check ($r.Removed -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $shader '111\shaders.bin'))) 'The Steam policy actually deletes the shader cache'
    Check (Test-Path -LiteralPath (Join-Path $common 'game.exe')) 'A sibling game installation survives the shader clean'

    # A junction inside the shader cache is not traversed.
    $jc = Join-Path $shader 'j'
    [void][IO.Directory]::CreateDirectory($jc)
    $outside = Join-Path $fixture 'outside-store'
    [void][IO.Directory]::CreateDirectory($outside)
    'keep' | Set-Content -LiteralPath (Join-Path $outside 'keep.bin')
    $linked = $false
    try { cmd /c mklink /J "$jc" "$outside" | Out-Null; $linked = $true } catch { $linked = $false }
    if ($linked) {
        'x' | Set-Content -LiteralPath (Join-Path $shader 'real.bin')
        $r = Invoke-CacheClean -Entry $steamEntry -SteamRoots @($lib)
        Check (Test-Path -LiteralPath (Join-Path $outside 'keep.bin')) 'A junction inside the shader cache is not followed'
        if (Test-Path -LiteralPath $jc) { [IO.Directory]::Delete($jc) }
    }

    # 28. VRChat freshness fails closed when the effective configuration cannot be proven.
    $cfgPath = Join-Path $fixture 'vrchat-config.json'
    $customA = Join-Path $fixture 'vr\CacheA'
    $customB = Join-Path $fixture 'vr\CacheB'
    $vrDefault = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA '..\LocalLow\VRChat\VRChat\Cache-WindowsPlayer'))
    $vrEntry = New-Entry 'VRChatCache' @($customA)
    $vrDefaultEntry = New-Entry 'VRChatCache' @($vrDefault)

    @{ cache_directory = $customA } | ConvertTo-Json -Compress | Set-Content -LiteralPath $cfgPath -Encoding UTF8
    Check ($null -eq (Test-CacheEntryFresh -Entry $vrEntry -ConfigPath $cfgPath)) 'An unchanged custom location is fresh'
    Check ($null -ne (Test-CacheEntryFresh -Entry $vrDefaultEntry -ConfigPath $cfgPath)) 'A default row is stale once a custom location is configured'

    @{ cache_directory = $customB } | ConvertTo-Json -Compress | Set-Content -LiteralPath $cfgPath -Encoding UTF8
    Check ($null -ne (Test-CacheEntryFresh -Entry $vrEntry -ConfigPath $cfgPath)) 'Custom to custom change is refused'

    @{ cache_directory = $vrDefault } | ConvertTo-Json -Compress | Set-Content -LiteralPath $cfgPath -Encoding UTF8
    Check ($null -ne (Test-CacheEntryFresh -Entry $vrEntry -ConfigPath $cfgPath)) 'Custom to default is refused for the custom row'
    Check ($null -eq (Test-CacheEntryFresh -Entry $vrDefaultEntry -ConfigPath $cfgPath)) 'Custom to default is fresh for the default row'

    @{ other = 'x' } | ConvertTo-Json -Compress | Set-Content -LiteralPath $cfgPath -Encoding UTF8
    Check ($null -eq (Test-CacheEntryFresh -Entry $vrDefaultEntry -ConfigPath $cfgPath)) 'A config without a custom path still allows the documented default'

    'not json at all' | Set-Content -LiteralPath $cfgPath -Encoding UTF8
    Check ($null -ne (Test-CacheEntryFresh -Entry $vrEntry -ConfigPath $cfgPath)) 'Malformed config refuses a custom row'
    Check ($null -ne (Test-CacheEntryFresh -Entry $vrDefaultEntry -ConfigPath $cfgPath)) 'Malformed config refuses even the default row'

    @{ cache_directory = 'C:\' } | ConvertTo-Json -Compress | Set-Content -LiteralPath $cfgPath -Encoding UTF8
    Check ($null -ne (Test-CacheEntryFresh -Entry $vrEntry -ConfigPath $cfgPath)) 'A drive-root cache value is never treated as fresh'

    Remove-Item -LiteralPath $cfgPath -Force
    Check ($null -ne (Test-CacheEntryFresh -Entry $vrEntry -ConfigPath $cfgPath)) 'A removed config refuses the previously custom row'
    Check ($null -eq (Test-CacheEntryFresh -Entry $vrDefaultEntry -ConfigPath $cfgPath)) 'A removed config still allows the default row'

    $vrState = Get-VRChatCacheState -ConfigPath $cfgPath
    Check ($vrState.State -eq 'absent') 'An absent config is reported as absent, not as a verified default'

    # 29. Multi-library Steam: an absent shader cache must not block a populated one.
    $libA = Join-Path $fixture 'steam-A'
    $libB = Join-Path $fixture 'steam-B'
    $libC = Join-Path $fixture 'steam-C'
    $shaderA = Join-Path $libA 'steamapps\shadercache'
    $shaderB = Join-Path $libB 'steamapps\shadercache'
    $shaderC = Join-Path $libC 'steamapps\shadercache'
    foreach ($lib in @($libA, $libB, $libC)) { [void][IO.Directory]::CreateDirectory((Join-Path $lib 'steamapps')) }
    [void][IO.Directory]::CreateDirectory((Join-Path $shaderA '111'))
    [void][IO.Directory]::CreateDirectory((Join-Path $shaderB '222'))
    'aaa' | Set-Content -LiteralPath (Join-Path $shaderA '111\a.bin')
    'bbbb' | Set-Content -LiteralPath (Join-Path $shaderB '222\b.bin')
    [void][IO.Directory]::CreateDirectory((Join-Path $libC 'steamapps\common\Game'))
    'game' | Set-Content -LiteralPath (Join-Path $libC 'steamapps\common\Game\game.exe')

    $twoLibs = New-Entry 'SteamShaderCache' @($shaderA, (Join-Path $libC 'steamapps\shadercache'))
    $twoLibs | Add-Member -NotePropertyName RootPolicy -NotePropertyValue 'SteamShader' -Force
    $twoLibs | Add-Member -NotePropertyName SteamRoots -NotePropertyValue @($libA, $libC) -Force
    Check ([string]::IsNullOrEmpty((Get-CacheEntryState $twoLibs))) 'A missing shader cache in one library does not block a populated one'
    $r = Invoke-CacheClean -Entry $twoLibs -SteamRoots @($libA, $libC)
    Check ($r.Removed -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $shaderA '111\a.bin'))) 'The populated library is cleaned while the empty one is skipped'
    Check (Test-Path -LiteralPath (Join-Path $libC 'steamapps\common\Game\game.exe')) 'A library with no shader cache keeps its games'

    # Two populated libraries are both cleanable.
    $bothLibs = New-Entry 'SteamShaderCache' @($shaderA, $shaderB)
    $bothLibs | Add-Member -NotePropertyName RootPolicy -NotePropertyValue 'SteamShader' -Force
    $bothLibs | Add-Member -NotePropertyName SteamRoots -NotePropertyValue @($libA, $libB) -Force
    [void][IO.Directory]::CreateDirectory((Join-Path $shaderA '111'))
    'a2' | Set-Content -LiteralPath (Join-Path $shaderA '111\a2.bin')
    Check ([string]::IsNullOrEmpty((Get-CacheEntryState $bothLibs))) 'Two populated libraries pass validation'
    $r = Invoke-CacheClean -Entry $bothLibs -SteamRoots @($libA, $libB)
    Check ($r.Removed -eq 2 -and -not (Test-Path -LiteralPath (Join-Path $shaderB '222\b.bin'))) 'Both libraries are cleaned'

    # 30. A library removed from Steam after the scan is refused, even though the row still lists it.
    [void][IO.Directory]::CreateDirectory((Join-Path $shaderB '222'))
    'stale' | Set-Content -LiteralPath (Join-Path $shaderB '222\stale.bin')
    $staleEntry = New-Entry 'SteamShaderCache' @($shaderA, $shaderB)
    $staleEntry | Add-Member -NotePropertyName RootPolicy -NotePropertyValue 'SteamShader' -Force
    $staleEntry | Add-Member -NotePropertyName SteamRoots -NotePropertyValue @($libA, $libB) -Force
    $r = Invoke-CacheClean -Entry $staleEntry -SteamRoots @($libA)
    Check (Test-Path -LiteralPath (Join-Path $shaderB '222\stale.bin')) 'A library missing from the live mapping is refused at delete time'

    # 31. A row with nothing present is not advertised as cleanable.
    $emptyEntry = New-Entry 'SteamShaderCache' @($shaderC)
    $emptyEntry | Add-Member -NotePropertyName RootPolicy -NotePropertyValue 'SteamShader' -Force
    $emptyEntry | Add-Member -NotePropertyName SteamRoots -NotePropertyValue @($libC) -Force
    Check ((Get-CacheEntryState $emptyEntry) -eq 'No cache folder present on this PC') 'A row with no existing folder is reported, not cleanable'

    # 32. Forged folders and junctions stay refused under the multi-library policy.
    $forged = Join-Path $libB 'steamapps\shadercache-forged'
    [void][IO.Directory]::CreateDirectory($forged)
    'f' | Set-Content -LiteralPath (Join-Path $forged 'f.bin')
    $forgedEntry = New-Entry 'SteamShaderCache' @($forged)
    $forgedEntry | Add-Member -NotePropertyName RootPolicy -NotePropertyValue 'SteamShader' -Force
    $forgedEntry | Add-Member -NotePropertyName SteamRoots -NotePropertyValue @($libA, $libB) -Force
    $r = Invoke-CacheClean -Entry $forgedEntry -SteamRoots @($libA, $libB)
    Check ($r.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $forged 'f.bin'))) 'A folder merely named like a shader cache is refused'

    $junctionTarget = Join-Path $fixture 'junction-store'
    [void][IO.Directory]::CreateDirectory($junctionTarget)
    'keep' | Set-Content -LiteralPath (Join-Path $junctionTarget 'keep.bin')
    $linkShader = Join-Path $libA 'steamapps\shaderlink'
    $made = $false
    try { cmd /c mklink /J "$linkShader" "$junctionTarget" | Out-Null; $made = $true } catch { $made = $false }
    if ($made) {
        Check (-not (Test-CleanupRoot -Path $linkShader -AllowAnyName -Policy SteamShader -SteamRoots @($libA)).Ok) 'A junction is never accepted as a shader cache'
        [IO.Directory]::Delete($linkShader)
    }

    # 33. A cache folder that became a regular file is refused, never deleted as a stray file.
    $crossA = Join-Path $libA 'steamapps\shadercache'
    $crossB = Join-Path $libB 'steamapps\shadercache'
    foreach ($dir in @($crossA, $crossB)) {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
        [void][IO.Directory]::CreateDirectory($dir)
    }
    [void][IO.Directory]::CreateDirectory((Join-Path $crossA '111'))
    'shader' | Set-Content -LiteralPath (Join-Path $crossA '111\s.bin')
    $crossEntry = New-Entry 'SteamShaderCache' @($crossA, $crossB)
    $crossEntry | Add-Member -NotePropertyName RootPolicy -NotePropertyValue 'SteamShader' -Force
    $crossEntry | Add-Member -NotePropertyName SteamRoots -NotePropertyValue @($libA, $libB) -Force
    Check ([string]::IsNullOrEmpty((Get-CacheEntryState $crossEntry))) 'Both scanned caches validate before the type change'
    # The second scanned cache is swapped for a regular file between scan and clean.
    Remove-Item -LiteralPath $crossB -Recurse -Force
    'not a cache' | Set-Content -LiteralPath $crossB
    $r = Invoke-CacheClean -Entry $crossEntry -SteamRoots @($libA, $libB)
    Check (Test-Path -LiteralPath $crossB -PathType Leaf) 'A cache path replaced by a file survives the cleanup'
    Check ((Get-Content -LiteralPath $crossB -Raw).Trim() -eq 'not a cache') 'The replacement file is untouched, not truncated or rewritten'
    Check ($r.Removed -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $crossA '111\s.bin'))) 'The still-valid cache in the same row is cleaned'

    # The scan does not advertise a row whose folder is now a file.
    $scanRow = @(Get-CacheScan -Catalog @($crossEntry))[0]
    Check ($scanRow.EligibleBytes -eq 0) 'A file where a cache folder belonged is not counted as eligible'

    # A wildcard row still cleans matching files: that is a real file pattern, not a cache root.
    $wildRoot = Join-Path $fixture 'wild\logs'
    [void][IO.Directory]::CreateDirectory($wildRoot)
    'old' | Set-Content -LiteralPath (Join-Path $wildRoot 'app-2020-01-01.log')
    (Get-Item -LiteralPath (Join-Path $wildRoot 'app-2020-01-01.log')).LastWriteTime = (Get-Date).AddDays(-30)
    $wildEntry = New-Entry 'WildcardLogs' @((Join-Path $wildRoot '*.log'))
    $r = Invoke-CacheClean -Entry $wildEntry
    Check ($r.Removed -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $wildRoot 'app-2020-01-01.log')) -and $r.Status -eq 'Completed') 'A wildcard log row still removes its matched files'

    Write-Host "PASS: $checks cache explorer checks. Fixtures under TEMP only." -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $fixture) {
        # Junctions must be removed as links, never followed into their target folder.
        Get-ChildItem -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
            ForEach-Object { [IO.Directory]::Delete($_.FullName) }
        Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}
