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

function Get-ModdingLogTargets {
    # Verified diagnostic logs from the modding tools themselves. Instance roots are user-selected,
    # so a portable install only appears when the operator points at it; nothing is guessed.
    param([string]$ModOrganizerRoot, [string]$VortexRoot, [string]$DynDolodRoot)
    $L = $env:LOCALAPPDATA; $A = $env:APPDATA
    $out = @()

    # MO2 keeps one logs folder per instance. A portable install puts it directly under the selected
    # root; global instances live under ModOrganizer\<instance>. Either way the folder has to prove it
    # is MO2 before its "logs" is accepted, so an arbitrary folder named logs is never authorized.
    $moRoot = if ($ModOrganizerRoot) { $ModOrganizerRoot } else { Join-Path $L 'ModOrganizer' }
    if (Test-Path -LiteralPath $moRoot -PathType Container) {
        $instances = @()
        if (Test-ModOrganizerRoot -Path $moRoot) { $instances += (Get-Item -LiteralPath $moRoot -Force) }
        foreach ($child in @(Get-ChildItem -LiteralPath $moRoot -Force -Directory -ErrorAction SilentlyContinue)) {
            if (Test-ModOrganizerRoot -Path $child.FullName) { $instances += $child }
        }
        foreach ($instance in $instances) {
            $logs = Join-Path $instance.FullName 'logs'
            if (-not (Test-Path -LiteralPath $logs -PathType Container)) { continue }
            $out += [pscustomobject]@{ Id = ('MO2_' + $instance.Name); Group = 'Modding'; Label = ("Mod Organizer 2 logs ({0})" -f $instance.Name)
                Path = $logs; Pattern = '^(mo_interface|usvfs-.*)\.log\d*$'; PatternText = 'mo_interface.log, usvfs-*.log'
                Process = @('ModOrganizer')
                Source = 'MO2 support: open the log folder from the instance menu' }
        }
    }

    # Vortex writes vortex.log plus numbered rotations next to its state file.
    $vortex = if ($VortexRoot) { $VortexRoot } else { Join-Path $A 'Vortex' }
    if (Test-Path -LiteralPath $vortex -PathType Container) {
        $out += [pscustomobject]@{ Id = 'Vortex'; Group = 'Modding'; Label = 'Vortex application logs'; Path = $vortex
            Pattern = '^vortex\d*\.log$'; PatternText = 'vortex.log, vortex1.log'; Process = @('Vortex')
            Source = 'Vortex logs sit beside its state file in %APPDATA%\Vortex' }
    }

    # DynDOLOD/TexGen/LODGen write plain .txt diagnostics into DynDOLOD\Logs.
    $dyndolod = if ($DynDolodRoot) { Join-Path $DynDolodRoot 'Logs' } else { $null }
    if ($dyndolod -and (Test-Path -LiteralPath $dyndolod -PathType Container)) {
        $out += [pscustomobject]@{ Id = 'DynDOLOD'; Group = 'Modding'; Label = 'DynDOLOD / TexGen / LODGen logs'; Path = $dyndolod
            Pattern = '^(DynDOLOD|TexGen|LODGen)_.*_log\.txt$'; PatternText = 'DynDOLOD_SSE_log.txt, TexGen_*, LODGen_*'; Process = @('DynDOLOD', 'TexGen', 'LODGen')
            Source = 'dyndolod.info: logs are written to DynDOLOD\Logs' }
    }
    return @($out)
}

function Test-ModOrganizerRoot {
    # Identity, not a folder name: MO2 always ships its executable, and an instance keeps
    # ModOrganizer.ini beside its logs. Anything else is just a folder that happens to be called logs.
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    foreach ($marker in @('ModOrganizer.exe', 'ModOrganizer.ini', 'nxmhandler.exe')) {
        if (Test-Path -LiteralPath (Join-Path $Path $marker) -PathType Leaf) { return $true }
    }
    return $false
}

function Get-SkyrimToolTargets {
    # Report-only data folders: profiles, mods, downloads and staging stay out of every deletion.
    $L = $env:LOCALAPPDATA; $A = $env:APPDATA
    $out = @()
    foreach ($p in @((Join-Path $L 'ModOrganizer'), (Join-Path $A 'Vortex'))) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            $out += [pscustomobject]@{ Id = (Split-Path $p -Leaf); Label = (("{0} data folder (report only)" -f (Split-Path $p -Leaf))); Path = $p }
        }
    }
    return @($out)
}

function Get-SkyrimBlockingProcess {
    # The process that owns a target, or $null when nothing is running. Skyrim rows are owned by the
    # game plus the loader for that game version; modding rows are owned by the tool writing them.
    param($Game, $Target)
    if ($Target -and $Target.PSObject.Properties['Process'] -and $Target.Process) { return @($Target.Process) }
    $names = @('SkyrimSE', 'SkyrimVR', 'skse64_loader', 'sksevr_loader')
    if ($Game -and $Game.Id -eq 'SkyrimVR') { $names = @('SkyrimVR', 'sksevr_loader') }
    elseif ($Game -and $Game.Id) { $names = @('SkyrimSE', 'skse64_loader') }
    return @($names)
}

function Test-SkyrimClosed {
    # A running game, loader or owning tool keeps its logs open, so nothing is deleted then.
    param($Game, $Target)
    foreach ($name in @(Get-SkyrimBlockingProcess -Game $Game -Target $Target)) {
        if (@(Get-Process -Name $name -ErrorAction SilentlyContinue).Count) { return $false }
    }
    return $true
}

function Get-SkyrimApprovedTarget {
    # Rebuilds the permitted target from the definitions, never from a caller-supplied row.
    param([string]$Id, [string]$DocumentsRoot, [string]$ModOrganizerRoot, [string]$VortexRoot, [string]$DynDolodRoot)
    foreach ($game in @(Get-SkyrimGames -DocumentsRoot $DocumentsRoot)) {
        foreach ($target in @(Get-SkyrimLogTargets -Game $game)) {
            if ($target.Id -eq $Id) { return [pscustomobject]@{ Target = $target; Game = $game; CloudSynced = $game.CloudSynced } }
        }
    }
    foreach ($target in @(Get-ModdingLogTargets -ModOrganizerRoot $ModOrganizerRoot -VortexRoot $VortexRoot -DynDolodRoot $DynDolodRoot)) {
        if ($target.Id -eq $Id) { return [pscustomobject]@{ Target = $target; Game = $null; CloudSynced = $false } }
    }
    return $null
}

function Remove-SkyrimLogFile {
    # The single approved bypass of the Documents protection. The caller names a target id and a
    # file, never a root or a pattern: both are rebuilt here from the game definitions.
    param([string]$Path, [string]$TargetId, [string]$DocumentsRoot, [string]$ModOrganizerRoot, [string]$VortexRoot, [string]$DynDolodRoot)
    $approved = Get-SkyrimApprovedTarget -Id $TargetId -DocumentsRoot $DocumentsRoot -ModOrganizerRoot $ModOrganizerRoot -VortexRoot $VortexRoot -DynDolodRoot $DynDolodRoot
    if (-not $approved -or $approved.CloudSynced) { return $false }
    # The owning process is rechecked here, immediately before the delete, so a tool or game that
    # started after the scan cannot have its open log removed underneath it.
    if (-not (Test-SkyrimClosed -Game $approved.Game -Target $approved.Target)) { return $false }
    $root = $approved.Target.Path
    $pattern = $approved.Target.Pattern
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
        if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        # A direct child only: any separator left in the relative part means a nested file.
        $relative = $full.Substring($rootFull.Length)
        if ($relative.IndexOfAny([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) -ge 0) { return $false }
        $name = Split-Path $full -Leaf
        if ($name -notmatch $pattern) { return $false }
        if (-not (Test-CleanPathWithoutLinks $full)) { return $false }
        $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) { return $false }
        Remove-Item -LiteralPath $full -Force -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-SkyrimScan {
    # One row per verified log folder. A row records what was true at scan time; nothing here is
    # an authorization to delete. Invoke-SkyrimClean re-derives every target before it touches a file.
    param([string]$DocumentsRoot, [string]$ModOrganizerRoot, [string]$VortexRoot, [string]$DynDolodRoot)
    $rows = @()
    foreach ($game in @(Get-SkyrimGames -DocumentsRoot $DocumentsRoot)) {
        foreach ($target in @(Get-SkyrimLogTargets -Game $game)) {
            $rows += New-SkyrimRow -Target $target -Group 'Skyrim' -Game $game.Id -CloudSynced $game.CloudSynced -BlockedBy (-not (Test-SkyrimClosed -Game $game))
        }
    }
    foreach ($target in @(Get-ModdingLogTargets -ModOrganizerRoot $ModOrganizerRoot -VortexRoot $VortexRoot -DynDolodRoot $DynDolodRoot)) {
        $rows += New-SkyrimRow -Target $target -Group 'Modding' -Game '' -CloudSynced $false -BlockedBy (-not (Test-SkyrimClosed -Target $target))
    }
    return @($rows)
}

function New-SkyrimRow {
    # Shared shaping for a scan row, so both groups report the same numbers the same way.
    param($Target, [string]$Group, [string]$Game, [bool]$CloudSynced, [bool]$BlockedBy)
    $files = @(Get-ChildItem -LiteralPath $Target.Path -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $Target.Pattern })
    $bytes = [long]0; $old = 0; $oldBytes = [long]0; $newest = $null
    $cutoff = (Get-Date).AddDays(-7)
    foreach ($f in $files) {
        $bytes += $f.Length
        if (-not $newest -or $f.LastWriteTime -gt $newest) { $newest = $f.LastWriteTime }
        if ($f.LastWriteTime -lt $cutoff) { $old++; $oldBytes += $f.Length }
    }
    [pscustomobject]@{ Id = $Target.Id; Group = $Group; Game = $Game; Label = $Target.Label; Path = $Target.Path
        Pattern = $Target.Pattern; PatternText = $Target.PatternText; Source = $Target.Source
        Files = $files.Count; Bytes = $bytes; OldFiles = $old; OldBytes = $oldBytes; Newest = $newest
        CloudSynced = $CloudSynced; Running = $BlockedBy }
}

function Invoke-SkyrimClean {
    # Re-derives every target from the definitions at execution time: processes, the Documents
    # known folder, cloud-sync state and the approved target list. A stale or forged row cannot
    # authorize anything, and a row whose folder moved is refused rather than followed.
    param([object[]]$Scan, [switch]$AnyAge, [string]$DocumentsRoot, [string]$ModOrganizerRoot, [string]$VortexRoot, [string]$DynDolodRoot)
    $totalRemoved = 0; $totalBytes = [long]0; $totalSkipped = 0
    $live = @{}
    foreach ($game in @(Get-SkyrimGames -DocumentsRoot $DocumentsRoot)) { $live[$game.Id] = $game }
    foreach ($row in $Scan) {
        if ($row.Group -ne 'Modding') {
            $game = $live[$row.Game]
            if (-not $game) { Write-Status Warn ("{0}: game folder is no longer present." -f $row.Id); continue }
            if ($game.CloudSynced) { Write-Status Warn ("{0}: cloud-synced Documents folder; skipped." -f $row.Id); continue }
            if (-not (Test-SkyrimClosed -Game $game)) { Write-Status Warn ("{0}: close Skyrim and its loader first." -f $row.Id); continue }
        }
        $approved = Get-SkyrimApprovedTarget -Id $row.Id -DocumentsRoot $DocumentsRoot -ModOrganizerRoot $ModOrganizerRoot -VortexRoot $VortexRoot -DynDolodRoot $DynDolodRoot
        if (-not $approved) { Write-Status Warn ("{0}: no approved log folder for this row." -f $row.Id); continue }
        if ($approved.CloudSynced) { Write-Status Warn ("{0}: cloud-synced folder; skipped." -f $row.Id); continue }
        $target = $approved.Target
        if ($target.Path -ne $row.Path) { Write-Status Warn ("{0}: folder changed since the scan; rescan." -f $row.Id); continue }
        if (-not (Test-CleanPathWithoutLinks $target.Path)) { Write-Status Warn ("{0}: linked path refused." -f $row.Id); continue }
        if (-not (Test-SkyrimClosed -Target $target)) { Write-Status Warn ("{0}: close the application that writes these logs first." -f $row.Id); continue }
        $cutoff = if ($AnyAge) { $null } else { (Get-Date).AddDays(-7) }
        $files = @(Get-ChildItem -LiteralPath $target.Path -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $target.Pattern })
        foreach ($file in $files) {
            if ($cutoff -and $file.LastWriteTime -ge $cutoff) { $totalSkipped++; continue }
            if (Remove-SkyrimLogFile -Path $file.FullName -TargetId $row.Id -DocumentsRoot $DocumentsRoot -ModOrganizerRoot $ModOrganizerRoot -VortexRoot $VortexRoot -DynDolodRoot $DynDolodRoot) {
                $totalRemoved++; $totalBytes += $file.Length
            } else { $totalSkipped++ }
        }
    }
    return [pscustomobject]@{ Removed = $totalRemoved; Skipped = $totalSkipped; Bytes = $totalBytes }
}

function Show-SkyrimReport {
    param([object[]]$Scan)
    $tools = @(Get-SkyrimToolTargets)
    Write-Host ''
    Write-Host '  SKYRIM & MODDING' -ForegroundColor Cyan
    if (-not $Scan.Count) { Write-Host '    No Skyrim or modding log folder was found.' -ForegroundColor DarkGray }
    foreach ($group in @('Skyrim', 'Modding')) {
        $rows = @($Scan | Where-Object Group -eq $group)
        if (-not $rows.Count) { continue }
        Write-Host ('    -- {0} --' -f $group) -ForegroundColor DarkCyan
        foreach ($row in $rows) {
            Write-Host ("    {0,-26} {1,10} {2,6}  {3}" -f $row.Id, (Format-Size $row.Bytes), ($row.Files.ToString() + 'f'), $row.Path) -ForegroundColor Gray
            Write-Host ("      {0}; older than 7 days: {1} file(s), {2}" -f $row.Label, $row.OldFiles, (Format-Size $row.OldBytes)) -ForegroundColor DarkGray
            if ($row.Running) { Write-Host '      Skyrim or its loader is running.' -ForegroundColor DarkYellow }
            if ($row.CloudSynced) { Write-Host '      Documents folder is cloud-synced; this row is report only.' -ForegroundColor DarkYellow }
        }
    }
    foreach ($tool in $tools) { Write-Host ("    {0,-26} report only  {1}" -f $tool.Id, $tool.Path) -ForegroundColor DarkYellow }
    Write-Host ''
    Write-Host '  Eligible: SKSE and Papyrus .log/.logN, MO2 mo_interface/usvfs logs, Vortex vortex*.log,' -ForegroundColor DarkGray
    Write-Host '  and DynDOLOD/TexGen/LODGen *_log.txt. Saves, configs, mods, profiles and state stay.' -ForegroundColor DarkGray
    Write-Host '  A portable MO2 or DynDOLOD install appears only when its folder is passed with' -ForegroundColor DarkGray
    Write-Host '  -ModOrganizerRoot / -DynDolodRoot; no drive is ever searched.' -ForegroundColor DarkGray
}

function Invoke-SkyrimCleaner {
    # Optional portable roots: a user-selected MO2 instance or DynDOLOD folder, never a drive scan.
    param([string]$ModOrganizerRoot, [string]$DynDolodRoot)
    while ($true) {
        $scan = @(Get-SkyrimScan -ModOrganizerRoot $ModOrganizerRoot -DynDolodRoot $DynDolodRoot)
        Show-SkyrimReport -Scan $scan
        Write-Host ''
        Write-Host '  [1] Rescan                    [2] Delete logs older than 7 days (SAFE)' -ForegroundColor Cyan
        Write-Host '  [3] Delete all matched logs   (HARD: any age, game closed)'
        Write-Host '  [4] Export JSON report        [5] Add a portable MO2 / DynDOLOD folder' -ForegroundColor Cyan
        Write-Host '  [0] Back'
        $choice = (Read-Host '  Select').Trim()
        switch ($choice) {
            '1' { continue }
            '2' {
                if (-not $scan.Count) { continue }
                Write-Host '  Deletes only .log/.logN files older than seven days in the SKSE and Papyrus folders.' -ForegroundColor Yellow
                if ((Read-Host '  Type CLEAN to continue').Trim() -ne 'CLEAN') { continue }
                $r = Invoke-SkyrimClean -Scan $scan -ModOrganizerRoot $ModOrganizerRoot -DynDolodRoot $DynDolodRoot
                Write-Status OK ("{0} removed, {1} skipped, {2} bytes" -f $r.Removed, $r.Skipped, $r.Bytes)
                Read-Host '  Press Enter' | Out-Null
            }
            '3' {
                if (-not $scan.Count) { continue }
                Write-Host '  HARD: every matched .log/.logN file, including recent ones. Saves and configs stay.' -ForegroundColor Yellow
                if ((Read-Host '  Type HARD to continue').Trim() -ne 'HARD') { continue }
                $r = Invoke-SkyrimClean -Scan $scan -AnyAge -ModOrganizerRoot $ModOrganizerRoot -DynDolodRoot $DynDolodRoot
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
            '5' {
                Write-Host '  Point at a portable MO2 install (the folder holding its instances) or a DynDOLOD folder.' -ForegroundColor Yellow
                Write-Host '  Nothing is scanned automatically; leave blank to skip.' -ForegroundColor DarkGray
                $mo = (Read-Host '  MO2 root').Trim()
                $dd = (Read-Host '  DynDOLOD root').Trim()
                if ($mo) {
                    if (Test-Path -LiteralPath $mo -PathType Container) { $ModOrganizerRoot = $mo } else { Write-Status Warn 'That MO2 folder does not exist.' }
                }
                if ($dd) {
                    if (Test-Path -LiteralPath (Join-Path $dd 'Logs') -PathType Container) { $DynDolodRoot = $dd }
                    else { Write-Status Warn 'That folder has no Logs subfolder; nothing will be listed for it.' }
                }
            }
            '0' { return }
            default { Write-Status Warn 'Invalid selection.' }
        }
    }
}
