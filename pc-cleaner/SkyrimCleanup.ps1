# Skyrim & modding cleanup. Reads the Windows Documents known folder, never searches drives, and
# deletes only files matching a verified diagnostic log pattern through one narrow, revalidated
# exception to the Documents protection. Everything else in the catalog is report-only.

function Get-SkyrimDocumentsRoot {
    # The known folder, not %USERPROFILE%\Documents: redirected profiles resolve correctly here.
    param([string]$Override)
    $docs = if ($Override) { $Override } else { [Environment]::GetFolderPath('MyDocuments') }
    if (-not $docs -or -not (Test-Path -LiteralPath $docs -PathType Container)) { return $null }
    try {
        if ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($docs)).DriveType -ne 'Fixed') { return $null }
    } catch { return $null }
    return [IO.Path]::GetFullPath($docs)
}

function Get-SkyrimGames {
    param([string]$DocumentsRoot)
    $docs = Get-SkyrimDocumentsRoot -Override $DocumentsRoot
    if (-not $docs) { return @() }
    $games = @(
        @{ Id = 'SkyrimSE'; Label = 'Skyrim Special/Anniversary Edition'; Folder = 'Skyrim Special Edition'; Process = 'SkyrimSE' },
        @{ Id = 'SkyrimVR'; Label = 'Skyrim VR'; Folder = 'Skyrim VR'; Process = 'SkyrimVR' }
    )
    foreach ($game in $games) {
        $base = Join-Path $docs ('My Games\' + $game.Folder)
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        [pscustomobject]@{
            Id = $game.Id; Label = $game.Label; Process = $game.Process; Base = $base
            CloudSynced = ($base -match '\\OneDrive\\' -or $base -match '\\Dropbox\\' -or $base -match '\\Google Drive\\')
        }
    }
}

function Get-SkyrimLogTargets {
    # Verified locations only: SKSE writes to <Documents>\My Games\<game>\SKSE, Papyrus to \Logs\Script.
    param($Game)
    $se = Join-Path $Game.Base 'SKSE'
    $script = Join-Path $Game.Base 'Logs\Script'
    $out = @()
    if (Test-Path -LiteralPath $se -PathType Container) {
        $out += [pscustomobject]@{ Id = "$($Game.Id)_SKSE"; Label = "$($Game.Label) SKSE and plugin logs"; Path = $se; Pattern = '^.*\.log\d*$'; PatternText = '*.log'; Source = 'SKSE64 readme: logs moved to My Games\Skyrim Special Edition\SKSE' }
    }
    if (Test-Path -LiteralPath $script -PathType Container) {
        $out += [pscustomobject]@{ Id = "$($Game.Id)_Papyrus"; Label = "$($Game.Label) Papyrus script logs"; Path = $script; Pattern = '^Papyrus.*\.log\d*$'; PatternText = 'Papyrus*.log'; Source = 'Skyrim Papyrus logging writes My Games\<game>\Logs\Script' }
    }
    return @($out)
}

function Get-SkyrimToolTargets {
    # Report-only: instance folders are user-selected, so nothing is deleted here.
    $L = $env:LOCALAPPDATA; $A = $env:APPDATA
    $out = @()
    foreach ($p in @((Join-Path $L 'ModOrganizer'), (Join-Path $A 'Vortex'))) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            $out += [pscustomobject]@{ Id = (Split-Path $p -Leaf); Label = ("{0} data folder (report only)" -f (Split-Path $p -Leaf)); Path = $p }
        }
    }
    return @($out)
}

function Test-SkyrimClosed {
    param($Game)
    $names = @('SkyrimSE', 'SkyrimVR', 'skse64_loader', 'ModOrganizer', 'Vortex')
    if ($Game -and $Game.Process) { $names = @($Game.Process, 'skse64_loader') }
    foreach ($name in $names) {
        if (@(Get-Process -Name $name -ErrorAction SilentlyContinue).Count) { return $false }
    }
    return $true
}

function Remove-SkyrimLogFile {
    # The single approved bypass of the Documents protection. Every condition is checked again here:
    # the file must sit directly under an approved game-log root, be a regular file whose name ends
    # in .log or .logN, and have no reparse point in any parent.
    param([string]$Path, [string]$Root, [string]$Pattern)
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        if ($full.Substring($rootFull.Length) -match '[\\/]') { return $false }
        $name = Split-Path $full -Leaf
        if ($name -notmatch $Pattern) { return $false }
        if (-not (Test-CleanPathWithoutLinks $full)) { return $false }
        $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) { return $false }
        Remove-Item -LiteralPath $full -Force -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-SkyrimScan {
    param([string]$DocumentsRoot)
    $games = @(Get-SkyrimGames -DocumentsRoot $DocumentsRoot)
    $rows = foreach ($game in $games) {
        foreach ($target in @(Get-SkyrimLogTargets -Game $game)) {
            $files = @(Get-ChildItem -LiteralPath $target.Path -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $target.Pattern })
            $bytes = [long]0; $old = 0; $oldBytes = [long]0; $newest = $null
            $cutoff = (Get-Date).AddDays(-7)
            foreach ($f in $files) {
                $bytes += $f.Length
                if (-not $newest -or $f.LastWriteTime -gt $newest) { $newest = $f.LastWriteTime }
                if ($f.LastWriteTime -lt $cutoff) { $old++; $oldBytes += $f.Length }
            }
            [pscustomobject]@{ Id = $target.Id; Game = $game.Id; Label = $target.Label; Path = $target.Path; Pattern = $target.Pattern; Source = $target.Source
                Files = $files.Count; Bytes = $bytes; OldFiles = $old; OldBytes = $oldBytes; Newest = $newest
                CloudSynced = $game.CloudSynced; Running = (-not (Test-SkyrimClosed -Game $game)) }
        }
    }
    return @($rows)
}

function Show-SkyrimReport {
    param([object[]]$Scan)
    $tools = @(Get-SkyrimToolTargets)
    Write-Host ''
    Write-Host '  SKYRIM & MODDING' -ForegroundColor Cyan
    if (-not $Scan.Count) { Write-Host '    No Skyrim SE/VR Documents folder was found.' -ForegroundColor DarkGray }
    foreach ($row in $Scan) {
        Write-Host ("    {0,-22} {1,10} {2,6}  {3}" -f $row.Id, (Format-Size $row.Bytes), ($row.Files.ToString() + 'f'), $row.Path) -ForegroundColor Gray
        Write-Host ("      {0}; older than 7 days: {1} file(s), {2}" -f $row.Label, $row.OldFiles, (Format-Size $row.OldBytes)) -ForegroundColor DarkGray
        if ($row.Running) { Write-Host '      Skyrim or a modding tool is running.' -ForegroundColor DarkYellow }
        if ($row.CloudSynced) { Write-Host '      Documents folder is cloud-synced; this row is report only.' -ForegroundColor DarkYellow }
    }
    foreach ($tool in $tools) { Write-Host ("    {0,-22} report only  {1}" -f $tool.Id, $tool.Path) -ForegroundColor DarkYellow }
    Write-Host ''
    Write-Host '  Only .log / .logN files are eligible. Saves, ini/json/toml/yaml/dll/pex/psc and' -ForegroundColor DarkGray
    Write-Host '  every other file stay, including in the SKSE folder.' -ForegroundColor DarkGray
}

function Invoke-SkyrimClean {
    param([object[]]$Scan, [switch]$AnyAge)
    $totalRemoved = 0; $totalBytes = [long]0; $totalSkipped = 0
    foreach ($row in $Scan) {
        if ($row.CloudSynced) { Write-Status Warn ("{0}: cloud-synced Documents folder; skipped." -f $row.Id); continue }
        if ($row.Running) { Write-Status Warn ("{0}: close Skyrim and modding tools first." -f $row.Id); continue }
        if (-not (Test-CleanPathWithoutLinks $row.Path)) { Write-Status Warn ("{0}: linked path refused." -f $row.Id); continue }
        $cutoff = if ($AnyAge) { $null } else { (Get-Date).AddDays(-7) }
        $files = @(Get-ChildItem -LiteralPath $row.Path -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $row.Pattern })
        foreach ($file in $files) {
            if ($cutoff -and $file.LastWriteTime -ge $cutoff) { $totalSkipped++; continue }
            if (Remove-SkyrimLogFile -Path $file.FullName -Root $row.Path -Pattern $row.Pattern) { $totalRemoved++; $totalBytes += $file.Length }
            else { $totalSkipped++ }
        }
    }
    return [pscustomobject]@{ Removed = $totalRemoved; Skipped = $totalSkipped; Bytes = $totalBytes }
}

function Invoke-SkyrimCleaner {
    while ($true) {
        $scan = @(Get-SkyrimScan)
        Show-SkyrimReport -Scan $scan
        Write-Host ''
        Write-Host '  [1] Rescan                    [2] Delete logs older than 7 days (SAFE)' -ForegroundColor Cyan
        Write-Host '  [3] Delete all matched logs   (HARD: any age, game closed)'
        Write-Host '  [4] Export JSON report' -ForegroundColor Cyan
        Write-Host '  [0] Back'
        $choice = (Read-Host '  Select').Trim()
        switch ($choice) {
            '1' { continue }
            '2' {
                if (-not $scan.Count) { continue }
                Write-Host '  Deletes only .log/.logN files older than seven days in the SKSE and Papyrus folders.' -ForegroundColor Yellow
                if ((Read-Host '  Type CLEAN to continue').Trim() -ne 'CLEAN') { continue }
                $r = Invoke-SkyrimClean -Scan $scan
                Write-Status OK ("{0} removed, {1} skipped, {2} bytes" -f $r.Removed, $r.Skipped, $r.Bytes)
                Read-Host '  Press Enter' | Out-Null
            }
            '3' {
                if (-not $scan.Count) { continue }
                Write-Host '  HARD: every matched .log/.logN file, including recent ones. Saves and configs stay.' -ForegroundColor Yellow
                if ((Read-Host '  Type HARD to continue').Trim() -ne 'HARD') { continue }
                $r = Invoke-SkyrimClean -Scan $scan -AnyAge
                Write-Status OK ("{0} removed, {1} skipped, {2} bytes" -f $r.Removed, $r.Skipped, $r.Bytes)
                Read-Host '  Press Enter' | Out-Null
            }
            '4' {
                $dir = Join-Path $StateRoot 'Reports'; [void][IO.Directory]::CreateDirectory($dir)
                $path = Join-Path $dir ('skyrim-scan_{0}_{1}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 8))
                [pscustomobject]@{ Tool = 'PC Cleaner'; Version = $Script:Version; Created = (Get-Date).ToString('o'); Items = @($scan | Select-Object Id, Game, Label, Path, Files, Bytes, OldFiles, OldBytes, CloudSynced, Running) } |
                    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
                Write-Status OK ("Report written: {0}" -f $path)
            }
            '0' { return }
            default { Write-Status Warn 'Invalid selection.' }
        }
    }
}
