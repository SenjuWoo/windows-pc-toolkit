# Cache Explorer: catalog, measurement and selective cleanup for AI, gaming and developer caches.
# Loaded by PC_Cleaner.ps1 in every mode (Menu, Scan, Library). It reuses that file's guards -
# Test-IsProtectedPath, Test-CleanPathWithoutLinks and Remove-ItemSafe - so deletion still has one
# choke point. Nothing here deletes without a user confirmation.

function Get-SteamInstallRoots {
    # Registry first: Steam can live outside the two default Program Files folders.
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        $prop = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($prop.SteamPath) { $roots.Add($prop.SteamPath) }
        if ($prop.InstallPath) { $roots.Add($prop.InstallPath) }
    }
    foreach ($fallback in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam")) {
        if ($fallback) { $roots.Add($fallback) }
    }
    return @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_ -ErrorAction SilentlyContinue) } | Select-Object -Unique)
}

function Get-SteamLibraryRoots {
    # Every root is validated before it is offered: it must be a local fixed drive with steamapps.
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($steam in @(Get-SteamInstallRoots)) {
        if (-not (Test-Path -LiteralPath (Join-Path $steam 'steamapps') -ErrorAction SilentlyContinue)) { continue }
        $roots.Add($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf -PathType Leaf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw -ErrorAction SilentlyContinue), '"path"\s+"([^"]+)"')) {
                $path = $m.Groups[1].Value.Replace('\\', '\')
                if (Test-Path -LiteralPath (Join-Path $path 'steamapps') -ErrorAction SilentlyContinue) { $roots.Add($path) }
            }
        }
    }
    $local = foreach ($root in $roots) {
        try { if ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($root)).DriveType -eq 'Fixed') { $root } } catch { }
    }
    return @($local | Select-Object -Unique)
}

function Get-VRChatCachePath {
    # Uses the configured cache_directory when it is a local fixed path; otherwise the default.
    $default = Join-Path $env:LOCALAPPDATA '..\LocalLow\VRChat\VRChat\Cache-WindowsPlayer'
    $config = Join-Path $env:LOCALAPPDATA '..\LocalLow\VRChat\VRChat\config.json'
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return $default }
    try { $json = Get-Content -LiteralPath $config -Raw -ErrorAction Stop | ConvertFrom-Json } catch { return $default }
    $custom = $json.cache_directory
    if (-not $custom) { return $default }
    try {
        if ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($custom)).DriveType -ne 'Fixed') { return $default }
        return [IO.Path]::GetFullPath($custom)
    } catch { return $default }
}

function Get-CacheCatalog {
    $L = $env:LOCALAPPDATA; $A = $env:APPDATA; $U = $env:USERPROFILE
    $codex  = if ($env:CODEX_HOME)  { $env:CODEX_HOME }  else { Join-Path $U '.codex' }
    $claude = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $U '.claude' }
    $hermes = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $L 'hermes' }
    $shaderPaths = @(); $steamTemp = @()
    foreach ($root in @(Get-SteamLibraryRoots)) {
        $shaderPaths += (Join-Path $root 'steamapps\shadercache')
        $steamTemp += (Join-Path $root 'steamapps\temp')
    }

    @(
        [pscustomobject]@{ Id='AntigravityCaches'; Section='AI'; Label='Antigravity editor caches'; Risk='SAFE'; Delete=$true; AgeDays=0; RequireProcess='Antigravity';
            Paths=@("$A\Antigravity\Cache","$A\Antigravity\Code Cache","$A\Antigravity\CachedData","$A\Antigravity\GPUCache"); Signature="$A\Antigravity\User";
            Impact='Rebuilt on next start. User, globalStorage, workspaceStorage, History and extensions are excluded.'; Source='Sibling User folder proves the layout' }
        [pscustomobject]@{ Id='CodexState'; Section='AI'; Label='Codex home (report only)'; Risk='REPORT'; Delete=$false; AgeDays=0;
            Paths=@((Join-Path $codex 'log')); Impact='Sessions, archived sessions, SQLite state, config, credentials, plugins and tmp\arg0 are never touched.'; Source='CODEX_HOME / %USERPROFILE%\.codex' }
        [pscustomobject]@{ Id='ClaudeState'; Section='AI'; Label='Claude home (report only)'; Risk='REPORT'; Delete=$false; AgeDays=0;
            Paths=@((Join-Path $claude 'shell-snapshots')); Impact='.claude.json, settings, projects, sessions, plugins, permissions and memories are never touched.'; Source='CLAUDE_CONFIG_DIR / %USERPROFILE%\.claude' }
        [pscustomobject]@{ Id='HermesScratch'; Section='AI'; Label='Hermes scratch cache (report only)'; Risk='REPORT'; Delete=$false; AgeDays=1;
            Paths=@((Join-Path $hermes 'cache\scratch')); Impact='Hermes prunes entries idle for 24h itself; state.db, sessions, skills and profiles are never touched.'; Source='Hermes-managed lifecycle' }

        [pscustomobject]@{ Id='SteamShaderCache'; Section='Gaming'; Label='Steam shader cache (per library)'; Risk='STRICT'; Delete=$true; AgeDays=0; RequireProcess='steam';
            Paths=$shaderPaths; Impact='Shaders recompile on next launch: stutter and possible re-download. Never touches common, compatdata or manifests.'; Source='Steam support: shader cache can be rebuilt' }
        [pscustomobject]@{ Id='SteamStaging'; Section='Gaming'; Label='Steam staging temp (report only)'; Risk='REPORT'; Delete=$false; AgeDays=0;
            Paths=$steamTemp; Impact='An interrupted update can leave files here that Steam still needs; nothing is removed.'; Source='steamapps\temp' }
        [pscustomobject]@{ Id='VRChatCache'; Section='Gaming'; Label='VRChat downloaded content cache'; Risk='CAREFUL'; Delete=$true; AgeDays=0; RequireProcess='VRChat';
            Paths=@((Get-VRChatCachePath)); Impact='Avatars and worlds download again. config.json, screenshots and local moderation data are outside this folder.'; Source='config.json cache_directory, else the documented default' }
        [pscustomobject]@{ Id='RobloxLogs'; Section='Gaming'; Label='Roblox diagnostic logs'; Risk='SAFE'; Delete=$true; AgeDays=7;
            Paths=@("$L\Roblox\logs\*.log*"); Impact='Logs only; Studio autosaves, projects, versions and plugins are untouched.'; Source='Roblox Studio debugging docs' }
        [pscustomobject]@{ Id='MinecraftLogs'; Section='Gaming'; Label='Minecraft logs'; Risk='SAFE'; Delete=$true; AgeDays=7;
            Paths=@("$A\.minecraft\logs\*.log*"); Impact='Logs only; saves, mods, resource packs and configs are untouched.'; Source='%APPDATA%\.minecraft\logs' }
        [pscustomobject]@{ Id='EpicWebCache'; Section='Gaming'; Label='Epic Games Launcher web cache (report only)'; Risk='REPORT'; Delete=$false; AgeDays=0;
            Paths=@("$L\EpicGamesLauncher\Saved\webcache*"); Impact='Measured only: the browser WebCache guard blocks every folder of this name, so the cleaner will not delete it. Clear it from the launcher instead.'; Source='Epic support: clear webcache after closing the launcher' }

        [pscustomobject]@{ Id='PipCache'; Section='Dev'; Label='pip download cache'; Risk='SAFE'; Delete=$true; AgeDays=0;
            Paths=@("$L\pip\Cache"); Impact='Packages download again on next install.'; Source='pip cache dir' }
        [pscustomobject]@{ Id='NpmCache'; Section='Dev'; Label='npm content cache'; Risk='SAFE'; Delete=$true; AgeDays=0;
            Paths=@("$L\npm-cache\_cacache"); Impact='Packages download again.'; Source='npm config cache' }
        [pscustomobject]@{ Id='NuGetHttpCache'; Section='Dev'; Label='NuGet HTTP cache'; Risk='SAFE'; Delete=$true; AgeDays=0;
            Paths=@("$L\NuGet\v3-cache"); Impact='Packages download again; the global packages folder is not touched.'; Source='NuGet http_cache' }
        [pscustomobject]@{ Id='UEDerivedData'; Section='Dev'; Label='Unreal DerivedDataCache'; Risk='STRICT'; Delete=$true; AgeDays=0; RequireProcess='UnrealEditor';
            Paths=@("$L\UnrealEngine\Common\DerivedDataCache"); Impact='Shader and asset derivatives rebuild: long first launch.'; Source='UE engine DDC' }
        [pscustomobject]@{ Id='GradleCaches'; Section='Dev'; Label='Gradle build caches'; Risk='STRICT'; Delete=$true; AgeDays=0; RequireProcess='java';
            Paths=@("$U\.gradle\caches"); Impact='Next build re-resolves dependencies and recompiles; no project source is touched.'; Source='Gradle default cache' }
        [pscustomobject]@{ Id='UnityLibrary'; Section='Dev'; Label='Unity project Library folders (report only)'; Risk='REPORT'; Delete=$false; AgeDays=0;
            Paths=@(); Impact='Per-project rebuild can take minutes to hours; select the project manually.'; Source='Not enumerated: project location is not discoverable safely' }
    )
}

function Resolve-CacheTargets {
    # One resolver for both measurement and deletion: a wildcard yields whatever it matches, a
    # literal directory yields itself (its children are candidates), a literal file yields itself.
    param($Entry)
    $targets = foreach ($raw in @($Entry.Paths)) {
        $path = [Environment]::ExpandEnvironmentVariables([string]$raw)
        if (-not $path) { continue }
        if ($path -match '[*?]') {
            foreach ($item in @(Get-Item -Path $path -Force -ErrorAction SilentlyContinue)) {
                [pscustomobject]@{ Path = $item.FullName; IsContainer = [bool]$item.PSIsContainer }
            }
        } elseif (Test-Path -LiteralPath $path -PathType Container) {
            [pscustomobject]@{ Path = $path; IsContainer = $true }
        } elseif (Test-Path -LiteralPath $path -PathType Leaf) {
            [pscustomobject]@{ Path = $path; IsContainer = $false }
        }
    }
    return @($targets)
}

function Get-CacheFilesBounded {
    # Streams files depth-first and stops at the cap; it never materialises a whole tree.
    # Reparse points and protected names are skipped here, matching the deletion guard.
    param([string[]]$Roots, [int]$MaxFiles = 50000, [hashtable]$Counter = @{ n = 0 })
    foreach ($root in $Roots) {
        if (-not (Test-CleanPathWithoutLinks $root)) { continue }
        $stack = New-Object Collections.Stack
        $stack.Push($root)
        while ($stack.Count) {
            foreach ($item in (Get-ChildItem -LiteralPath $stack.Pop() -Force -ErrorAction SilentlyContinue)) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if (Test-IsProtectedPath $item.FullName) { continue }
                if ($item.PSIsContainer) { $stack.Push($item.FullName); continue }
                if ($Counter.n -ge $MaxFiles) { return }
                $Counter.n++
                $item
            }
        }
    }
}

function Get-CacheEntryState {
    param($Entry)
    if ($Entry.Signature -and -not (Test-Path -LiteralPath $Entry.Signature)) { return 'Layout not verified on this PC' }
    if ($Entry.RequireProcess -and @(Get-Process -Name $Entry.RequireProcess -ErrorAction SilentlyContinue).Count) { return "$($Entry.RequireProcess) is running" }
    return ''
}

function Get-CacheEntryMeasure {
    # Reports discovered bytes and the subset that the current age rule would delete.
    param($Entry, [int]$MaxFiles = 50000)
    $counter = @{ n = 0 }
    $discovered = [long]0; $eligible = [long]0; $newest = $null; $capped = $false
    $cutoff = if ($Entry.AgeDays) { (Get-Date).AddDays(-[double]$Entry.AgeDays) } else { $null }
    $targets = @(Resolve-CacheTargets $Entry)
    $usable = 0
    foreach ($target in $targets) {
        $roots = if ($target.IsContainer) { @($target.Path) } else { @() }
        if (-not $target.IsContainer) {
            $file = Get-Item -LiteralPath $target.Path -Force -ErrorAction SilentlyContinue
            if ($file) {
                $discovered += $file.Length
                if (-not $cutoff -or $file.LastWriteTime -lt $cutoff) { $eligible += $file.Length }
                if (-not $newest -or $file.LastWriteTime -gt $newest) { $newest = $file.LastWriteTime }
            }
            continue
        }
        if (-not (Test-CleanPathWithoutLinks $target.Path)) { continue }
        $usable++
        $files = @(Get-CacheFilesBounded -Roots $roots -MaxFiles $MaxFiles -Counter $counter)
        foreach ($file in $files) {
            $discovered += $file.Length
            if (-not $cutoff -or $file.LastWriteTime -lt $cutoff) { $eligible += $file.Length }
            if (-not $newest -or $file.LastWriteTime -gt $newest) { $newest = $file.LastWriteTime }
        }
        if ($counter.n -ge $MaxFiles) { $capped = $true }
    }
    [pscustomobject]@{ Bytes = $discovered; EligibleBytes = $eligible; Files = $counter.n; Newest = $newest; Capped = $capped
        Present = ($discovered -gt 0 -or $usable -gt 0); Paths = @($targets | ForEach-Object Path) }
}

function Get-CacheScan {
    param([object[]]$Catalog)
    if (-not $Catalog) { $Catalog = @(Get-CacheCatalog) }
    $scan = foreach ($entry in $Catalog) {
        $measure = Get-CacheEntryMeasure -Entry $entry
        [pscustomobject]@{ Id = $entry.Id; Section = $entry.Section; Label = $entry.Label; Risk = $entry.Risk; Delete = $entry.Delete
            Present = $measure.Present; Bytes = $measure.Bytes; EligibleBytes = $measure.EligibleBytes
            SizeText = (Format-Size $measure.EligibleBytes); DiscoveredText = (Format-Size $measure.Bytes)
            Files = $measure.Files; Newest = $measure.Newest; Capped = $measure.Capped
            State = (Get-CacheEntryState $entry); Paths = $measure.Paths; Entry = $entry }
    }
    return @($scan)
}

function Show-CacheReport {
    param([object[]]$Scan)
    if (-not $Scan) { return }
    foreach ($group in @('AI', 'Gaming', 'Dev')) {
        $rows = @($Scan | Where-Object Section -eq $group)
        if (-not $rows.Count) { continue }
        Write-Host ''
        Write-Host ("  {0}" -f $group.ToUpper()) -ForegroundColor Cyan
        foreach ($row in $rows) {
            $age = if ($row.Newest) { ('{0:N0}d' -f ((Get-Date) - $row.Newest).TotalDays) } else { '-' }
            $size = if ($row.Present) { Format-Size $row.EligibleBytes } else { '-' }
            $mode = if ($row.Delete) { 'clean ' + $row.Risk } else { 'REPORT ONLY' }
            Write-Host ("    {0,-18} {1,10} {2,7} {3,8}  {4}" -f $row.Id, $size, ($row.Files.ToString() + 'f'), $age, $mode) -ForegroundColor $(if ($row.Delete) { 'Gray' } else { 'DarkYellow' })
            if ($row.Present -and $row.Bytes -ne $row.EligibleBytes) { Write-Host ("      {0} eligible of {1} found (age rule)" -f (Format-Size $row.EligibleBytes), (Format-Size $row.Bytes)) -ForegroundColor DarkGray }
            if ($row.State) { Write-Host ("      {0}" -f $row.State) -ForegroundColor DarkYellow }
            if ($row.Capped) { Write-Host '      Scan capped; sizes are lower bounds.' -ForegroundColor DarkYellow }
        }
    }
    Write-Host ''
    Write-Host '  Sizes are scan estimates. Cleanup reports the bytes it actually removed.' -ForegroundColor DarkGray
}

function Show-CacheDetail {
    param([object[]]$Scan)
    foreach ($row in $Scan) {
        Write-Host ''
        Write-Host ("  {0}  [{1}/{2}]  {3}" -f $row.Id, $row.Section, $row.Risk, $row.Label) -ForegroundColor Cyan
        Write-Host ("    eligible {0} of {1} found, {2} files, newest {3}" -f (Format-Size $row.EligibleBytes), (Format-Size $row.Bytes), $row.Files, $(if ($row.Newest) { $row.Newest.ToString('u') } else { 'n/a' }))
        Write-Host ("    source : {0}" -f $row.Entry.Source)
        Write-Host ("    impact : {0}" -f $row.Entry.Impact)
        if ($row.Entry.AgeDays) { Write-Host ("    age    : only files older than {0} days" -f $row.Entry.AgeDays) }
        if ($row.State) { Write-Host ("    state  : {0}" -f $row.State) -ForegroundColor DarkYellow }
        foreach ($path in $row.Paths) { Write-Host ("    path   : {0}" -f $path) -ForegroundColor DarkGray }
    }
}

function Export-CacheScan {
    param([object[]]$Scan)
    if (-not $Scan) { throw 'Scan first.' }
    $dir = Join-Path $StateRoot 'Reports'; [void][IO.Directory]::CreateDirectory($dir)
    $path = Join-Path $dir ('cache-scan_{0}_{1}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 8))
    $rows = $Scan | Select-Object Id, Section, Label, Risk, Delete, Present, Bytes, EligibleBytes, Files, Capped, State, Paths, @{n = 'Newest'; e = { if ($_.Newest) { $_.Newest.ToString('o') } } }
    [pscustomobject]@{ Tool = 'PC Cleaner'; Version = $Script:Version; Created = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME; Items = @($rows) } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-CacheClean {
    param($Entry)
    $result = [pscustomobject]@{ Id = $Entry.Id; Status = 'Completed'; Removed = 0; Skipped = 0; Bytes = [long]0; Note = '' }
    if (-not $Entry.Delete) { $result.Status = 'Skipped'; $result.Note = 'Review only; kept all files.'; return $result }
    $state = Get-CacheEntryState $Entry
    if ($state) { $result.Status = 'Skipped'; $result.Note = $state; return $result }
    $cutoff = if ($Entry.AgeDays) { (Get-Date).AddDays(-[double]$Entry.AgeDays) } else { $null }
    foreach ($target in @(Resolve-CacheTargets $Entry)) {
        if (-not $target.IsContainer) {
            $file = Get-Item -LiteralPath $target.Path -Force -ErrorAction SilentlyContinue
            if (-not $file) { continue }
            if ($cutoff -and $file.LastWriteTime -ge $cutoff) { $result.Skipped++; continue }
            if (Remove-ItemSafe -Path $file.FullName) { $result.Removed++; $result.Bytes += [long]$file.Length }
            else { $result.Skipped++ }
            continue
        }
        if ((Test-IsProtectedPath $target.Path) -or -not (Test-CleanPathWithoutLinks $target.Path)) { $result.Skipped++; continue }
        # A cache root that holds a protected folder is a different layout than expected: keep it whole.
        $blockedChild = @(Get-ChildItem -LiteralPath $target.Path -Force -ErrorAction SilentlyContinue | Where-Object { Test-IsProtectedPath $_.FullName } | Select-Object -First 1)
        if ($blockedChild.Count) { $result.Skipped++; $result.Note = 'Protected folder inside; kept all files.'; continue }
        # Each file is age-checked and revalidated on its own, so a fresh file inside an old tree stays.
        $files = @(Get-CacheFilesBounded -Roots @($target.Path) -Counter @{ n = 0 })
        foreach ($file in $files) {
            if ($cutoff -and $file.LastWriteTime -ge $cutoff) { $result.Skipped++; continue }
            if (Remove-ItemSafe -Path $file.FullName) { $result.Removed++; $result.Bytes += [long]$file.Length }
            else { $result.Skipped++ }
        }
        # Remove only what became empty; never a directory that still holds files.
        Get-ChildItem -LiteralPath $target.Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { -not @(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue).Count -and -not (Test-IsProtectedPath $_.FullName) } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }
    return $result
}

function Invoke-CacheExplorer {
    $catalog = @(Get-CacheCatalog)
    Write-Host ''
    Write-Host '  Scanning AI, gaming and developer caches (read-only, bounded)...' -ForegroundColor Cyan
    $scan = @(Get-CacheScan -Catalog $catalog)
    while ($true) {
        Show-CacheReport -Scan $scan
        Write-Host ''
        Write-Host '  [1] Rescan            [2] Review every candidate (paths, source, impact)' -ForegroundColor Cyan
        Write-Host '  [3] Clean SAFE caches [4] Clean one category by id'
        Write-Host '  [5] Export JSON report' -ForegroundColor Cyan
        Write-Host '  [0] Back'
        $choice = (Read-Host '  Select').Trim()
        switch ($choice) {
            '1' { $scan = @(Get-CacheScan -Catalog $catalog) }
            '2' { Show-CacheDetail -Scan $scan; Read-Host '  Press Enter' | Out-Null }
            '3' {
                $targets = @($scan | Where-Object { $_.Delete -and $_.Present -and $_.Risk -eq 'SAFE' -and -not $_.State })
                if (-not $targets.Count) { Write-Status Info 'No SAFE cache is present.'; continue }
                Write-Host ('  About to clean: ' + (($targets | ForEach-Object Id) -join ', ')) -ForegroundColor Yellow
                Write-Host '  Cache deletion is irreversible; the contents are downloaded or rebuilt by the app.' -ForegroundColor Yellow
                if ((Read-Host '  Type CLEAN to continue').Trim() -ne 'CLEAN') { continue }
                foreach ($row in $targets) {
                    $r = Invoke-CacheClean -Entry $row.Entry
                    $level = if ($r.Status -eq 'Completed') { 'OK' } else { 'Warn' }
                    Write-Status $level ("{0}: {1} removed, {2} skipped, {3} bytes" -f $r.Id, $r.Removed, $r.Skipped, $r.Bytes)
                }
                $scan = @(Get-CacheScan -Catalog $catalog)
            }
            '4' {
                $id = (Read-Host '  Category id (see list)').Trim()
                $row = $scan | Where-Object { $_.Id -eq $id } | Select-Object -First 1
                if (-not $row) { Write-Status Warn 'Unknown id.'; continue }
                if (-not $row.Delete) { Write-Status Warn ("{0} is report only: {1}" -f $row.Id, $row.Entry.Impact); continue }
                if ($row.State) { Write-Status Warn $row.State; continue }
                Write-Host ("  {0}: {1} eligible - {2}" -f $row.Id, (Format-Size $row.EligibleBytes), $row.Entry.Impact) -ForegroundColor Yellow
                if ((Read-Host ('  Type ' + $row.Id + ' to confirm')).Trim() -ne $row.Id) { continue }
                $r = Invoke-CacheClean -Entry $row.Entry
                $level = if ($r.Status -eq 'Completed') { 'OK' } else { 'Warn' }
                Write-Status $level ("{0}: {1} removed, {2} skipped, {3} bytes" -f $r.Id, $r.Removed, $r.Skipped, $r.Bytes)
                $scan = @(Get-CacheScan -Catalog $catalog)
            }
            '5' { $path = Export-CacheScan -Scan $scan; Write-Status OK ("Report written: {0}" -f $path) }
            '0' { return }
            default { Write-Status Warn 'Invalid selection.' }
        }
    }
}
