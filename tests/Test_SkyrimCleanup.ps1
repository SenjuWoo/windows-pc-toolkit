# Skyrim log-cleanup regression suite. Fixtures only, under TEMP, using a fake Documents
# root so the real profile and the real Skyrim folder are never touched.
#requires -version 5.1
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$checks = 0
function Check([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "TEST FAILED: $Message" }; $script:checks++ }

$cleaner = Join-Path $Root 'pc-cleaner\PC_Cleaner.ps1'
if (-not (Test-Path -LiteralPath $cleaner)) { $cleaner = Join-Path $Root 'Pc Cleaner\PC_Cleaner.ps1' }
$fixture = Join-Path $env:TEMP ('ToolkitSkyrim_' + [guid]::NewGuid().ToString('N'))
$docs = Join-Path $fixture 'Documents'
# The machine's own MO2/Vortex/DynDOLOD folders must never enter a fixture run.
$noTools = Join-Path $fixture 'no-tools'
[void][IO.Directory]::CreateDirectory($docs)
try {
    . $cleaner -Action Library
    $StateRoot = Join-Path $fixture 'State'
    [void][IO.Directory]::CreateDirectory($StateRoot)

    $base = Join-Path $docs 'My Games\Skyrim Special Edition'
    $skse = Join-Path $base 'SKSE'
    $papyrus = Join-Path $base 'Logs\Script'
    $saves = Join-Path $docs 'My Games\Skyrim Special Edition\Saves'
    [void][IO.Directory]::CreateDirectory($skse)
    [void][IO.Directory]::CreateDirectory($papyrus)
    [void][IO.Directory]::CreateDirectory($saves)

    # Older than the SAFE window and recent, in both folders, plus files that must never move.
    'skse' | Set-Content -LiteralPath (Join-Path $skse 'skse64.log')
    'loader' | Set-Content -LiteralPath (Join-Path $skse 'skse64_loader.log')
    'plugin' | Set-Content -LiteralPath (Join-Path $skse 'SkyUI.log')
    'cfg' | Set-Content -LiteralPath (Join-Path $skse 'skse.ini')
    'json' | Set-Content -LiteralPath (Join-Path $skse 'settings.json')
    'dll' | Set-Content -LiteralPath (Join-Path $skse 'plugin.dll')
    'unknown' | Set-Content -LiteralPath (Join-Path $skse 'notes.txt')
    'crash' | Set-Content -LiteralPath (Join-Path $skse 'crash-2026-01-01.log')
    'pap' | Set-Content -LiteralPath (Join-Path $papyrus 'Papyrus.0.log')
    'pap1' | Set-Content -LiteralPath (Join-Path $papyrus 'Papyrus.1.log')
    'save' | Set-Content -LiteralPath (Join-Path $saves 'save1.ess')
    $old = (Get-Date).AddDays(-20)
    foreach ($f in @('skse64.log', 'skse64_loader.log', 'SkyUI.log', 'crash-2026-01-01.log')) { (Get-Item -LiteralPath (Join-Path $skse $f)).LastWriteTime = $old }
    (Get-Item -LiteralPath (Join-Path $papyrus 'Papyrus.0.log')).LastWriteTime = $old

    $scan = @(Get-SkyrimScan -DocumentsRoot $docs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools)
    Check ($scan.Count -eq 2) 'SE SKSE and Papyrus folders are both detected'
    $skseRow = $scan | Where-Object Id -eq 'SkyrimSE_SKSE'
    Check ($skseRow.Files -eq 4) 'Only .log files are counted in the SKSE folder'
    Check ($skseRow.OldFiles -eq 4) 'All four fixture logs are older than the SAFE window'

    # SAFE removes only old .log files; configs, dlls, unknown types and saves stay.
    $r = Invoke-SkyrimClean -Scan $scan -DocumentsRoot $docs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools
    Check ($r.Removed -eq 5 -and $r.Skipped -eq 1) 'SAFE removes the aged logs and keeps the recent one'
    Check ((Test-Path -LiteralPath (Join-Path $skse 'skse.ini')) -and (Test-Path -LiteralPath (Join-Path $skse 'settings.json'))) 'SKSE configuration survives'
    Check ((Test-Path -LiteralPath (Join-Path $skse 'plugin.dll')) -and (Test-Path -LiteralPath (Join-Path $skse 'notes.txt'))) 'DLL and unknown file types in the SKSE folder survive'
    Check (Test-Path -LiteralPath (Join-Path $saves 'save1.ess')) 'A save next to the logs survives'

    # A fresh log is kept by SAFE and removed by HARD.
    'fresh' | Set-Content -LiteralPath (Join-Path $skse 'skse64.log')
    $scan = @(Get-SkyrimScan -DocumentsRoot $docs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools)
    $safe = Invoke-SkyrimClean -Scan $scan -DocumentsRoot $docs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools
    Check ($safe.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $skse 'skse64.log'))) 'SAFE keeps a recent log'
    $hard = Invoke-SkyrimClean -Scan $scan -AnyAge -DocumentsRoot $docs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools
    Check ($hard.Removed -eq 2 -and -not (Test-Path -LiteralPath (Join-Path $skse 'skse64.log'))) 'HARD removes recent logs'

    # The Documents guard is not weakened: the same name outside the approved root is refused.
    $elsewhere = Join-Path $docs 'Random\SKSE'
    [void][IO.Directory]::CreateDirectory($elsewhere)
    'x' | Set-Content -LiteralPath (Join-Path $elsewhere 'skse64.log')
    $refused = Remove-SkyrimLogFile -Path (Join-Path $elsewhere 'skse64.log') -TargetId 'SkyrimSE_SKSE' -DocumentsRoot $docs
    Check (-not $refused -and (Test-Path -LiteralPath (Join-Path $elsewhere 'skse64.log'))) 'A log outside the approved folder is refused'
    Check (Test-IsProtectedPath (Join-Path $skse 'skse64.log')) 'Documents is still a protected segment'

    # A non-log file cannot be removed even when it sits in the approved folder.
    $refused = Remove-SkyrimLogFile -Path (Join-Path $skse 'skse.ini') -TargetId 'SkyrimSE_SKSE' -DocumentsRoot $docs
    Check (-not $refused -and (Test-Path -LiteralPath (Join-Path $skse 'skse.ini'))) 'A non-log file in the approved folder is refused'

    # Nested path and a junction are refused.
    $nested = Join-Path $skse 'deeper'
    [void][IO.Directory]::CreateDirectory($nested)
    'n' | Set-Content -LiteralPath (Join-Path $nested 'skse64.log')
    Check (-not (Remove-SkyrimLogFile -Path (Join-Path $nested 'skse64.log') -TargetId 'SkyrimSE_SKSE' -DocumentsRoot $docs)) 'A nested file is outside the approved root'

    # Cloud-synced Documents stays report-only.
    $cloudDocs = Join-Path $fixture 'OneDrive\Documents'
    [void][IO.Directory]::CreateDirectory((Join-Path $cloudDocs 'My Games\Skyrim Special Edition\SKSE'))
    'c' | Set-Content -LiteralPath (Join-Path $cloudDocs 'My Games\Skyrim Special Edition\SKSE\skse64.log')
    $cloudScan = @(Get-SkyrimScan -DocumentsRoot $cloudDocs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools)
    Check ($cloudScan.Count -eq 1 -and $cloudScan[0].CloudSynced) 'A cloud-synced Documents folder is detected'
    $cloudResult = Invoke-SkyrimClean -Scan $cloudScan -AnyAge -DocumentsRoot $cloudDocs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools
    Check ($cloudResult.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $cloudDocs 'My Games\Skyrim Special Edition\SKSE\skse64.log'))) 'Cloud-synced logs are never deleted'

    # An unrelated document in Documents is untouched by a scan.
    $doc = Join-Path $docs 'thesis.docx'
    'text' | Set-Content -LiteralPath $doc
    $scan = @(Get-SkyrimScan -DocumentsRoot $docs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools)
    Invoke-SkyrimClean -Scan $scan -AnyAge -DocumentsRoot $docs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools | Out-Null
    Check (Test-Path -LiteralPath $doc) 'Unrelated documents are untouched'

    # P0: a forged scan row cannot authorize a Documents file, a running game blocks execution,
    # a changed Documents root blocks, and a directory named like a log is refused.
    'thesis' | Set-Content -LiteralPath (Join-Path $docs 'thesis.docx')
    $forged = [pscustomobject]@{ Id = 'SkyrimSE_SKSE'; Game = 'SkyrimSE'; Label = 'forged'; Path = $docs; Pattern = '^.*$'; Source = 'forged'
        Files = 1; Bytes = 6; OldFiles = 1; OldBytes = 6; Newest = (Get-Date).AddDays(-30); CloudSynced = $false; Running = $false }
    $r = Invoke-SkyrimClean -Scan @($forged) -AnyAge -DocumentsRoot $docs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools
    Check ($r.Removed -eq 0 -and $r.Skipped -eq 0) 'A forged scan row deletes nothing'
    Check (Test-Path -LiteralPath (Join-Path $docs 'thesis.docx')) 'A forged row cannot reach a document'

    'fresh' | Set-Content -LiteralPath (Join-Path $skse 'skse64.log')
    $scan = @(Get-SkyrimScan -DocumentsRoot $docs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools)
    $originalClosed = ${function:Test-SkyrimClosed}
    function Test-SkyrimClosed { param($Game) return $false }
    try {
        $r = Invoke-SkyrimClean -Scan $scan -AnyAge -DocumentsRoot $docs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools
        Check ($r.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $skse 'skse64.log'))) 'A game detected as running at cleanup time blocks deletion'
    } finally { Set-Item -Path function:Test-SkyrimClosed -Value $originalClosed }

    $r = Invoke-SkyrimClean -Scan $scan -AnyAge -DocumentsRoot $cloudDocs -ModOrganizerRoot $noTools -VortexRoot $noTools -DynDolodRoot $noTools
    Check ($r.Removed -eq 0 -and (Test-Path -LiteralPath (Join-Path $skse 'skse64.log'))) 'A Documents root that changed to a cloud path blocks deletion'

    $dirLog = Join-Path $skse 'skse64_loader.log'
    [void][IO.Directory]::CreateDirectory($dirLog)
    Check (-not (Remove-SkyrimLogFile -Path $dirLog -TargetId 'SkyrimSE_SKSE' -DocumentsRoot $docs)) 'A directory named like a log is refused'
    [IO.Directory]::Delete($dirLog)

    # Modding tools: only the verified diagnostic logs, never profiles, mods or staging.
    $mo = Join-Path $fixture 'mo'
    $moLogs = Join-Path $mo 'Instance1\logs'
    [void][IO.Directory]::CreateDirectory($moLogs)
    [void][IO.Directory]::CreateDirectory((Join-Path $mo 'Instance1\mods\SomeMod'))
    'm' | Set-Content -LiteralPath (Join-Path $moLogs 'mo_interface.log')
    'u' | Set-Content -LiteralPath (Join-Path $moLogs 'usvfs-2026-01-01.log')
    'k' | Set-Content -LiteralPath (Join-Path $mo 'Instance1\mods\SomeMod\important.esp')

    $vortex = Join-Path $fixture 'vortex'
    [void][IO.Directory]::CreateDirectory($vortex)
    'v' | Set-Content -LiteralPath (Join-Path $vortex 'vortex.log')
    'v1' | Set-Content -LiteralPath (Join-Path $vortex 'vortex1.log')
    'db' | Set-Content -LiteralPath (Join-Path $vortex 'state.v2')

    $dd = Join-Path $fixture 'dyndolod'
    [void][IO.Directory]::CreateDirectory((Join-Path $dd 'Logs'))
    'd' | Set-Content -LiteralPath (Join-Path $dd 'Logs\DynDOLOD_SSE_log.txt')
    't' | Set-Content -LiteralPath (Join-Path $dd 'Logs\TexGen_SSE_log.txt')
    'o' | Set-Content -LiteralPath (Join-Path $dd 'Logs\LODGen_SSE_Tamriel_log.txt')
    'x' | Set-Content -LiteralPath (Join-Path $dd 'Logs\notes.txt')

    $rows = @(Get-SkyrimScan -DocumentsRoot $docs -ModOrganizerRoot $mo -VortexRoot $vortex -DynDolodRoot $dd)
    $moRow = $rows | Where-Object Id -eq 'MO2_Instance1'
    Check ($null -ne $moRow -and $moRow.Files -eq 2) 'MO2 instance logs are detected with only the two log names'
    $vRow = $rows | Where-Object Id -eq 'Vortex'
    Check ($vRow.Files -eq 2) 'Vortex logs are detected without its state files'
    $dRow = $rows | Where-Object Id -eq 'DynDOLOD'
    Check ($dRow.Files -eq 3) 'DynDOLOD, TexGen and LODGen logs are detected; notes.txt is not'

    # Only the tool rows: the Skyrim rows in this scan point at logs a earlier assertion already used.
    $toolRows = @($rows | Where-Object Group -eq 'Modding')
    $r = Invoke-SkyrimClean -Scan $toolRows -AnyAge -DocumentsRoot $docs -ModOrganizerRoot $mo -VortexRoot $vortex -DynDolodRoot $dd
    Check ($r.Removed -eq 7) 'The tool rows remove exactly the seven verified diagnostic logs'
    Check (Test-Path -LiteralPath (Join-Path $mo 'Instance1\mods\SomeMod\important.esp')) 'MO2 mod files survive'
    Check (Test-Path -LiteralPath (Join-Path $vortex 'state.v2')) 'Vortex state survives'
    Check (Test-Path -LiteralPath (Join-Path $dd 'Logs\notes.txt')) 'An unrelated file in the log folder survives'

    Write-Host "PASS: $checks Skyrim cleanup checks. Fixtures under TEMP only." -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $fixture) {
        Get-ChildItem -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
            ForEach-Object { [IO.Directory]::Delete($_.FullName) }
        Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}
