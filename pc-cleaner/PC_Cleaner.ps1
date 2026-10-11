#requires -version 5.1
<#
.SYNOPSIS
    PC Cleaner v1.1.2 - scan-first disk cleanup and registry care for Windows 10/11.
.DESCRIPTION
    Every category is labeled with what it is and why it is safe. Nothing is
    deleted without an explicit profile/pick and a confirmation. User data -
    documents, browser cookies/logins/history, app state, AI model stores - is
    never deleted: one protected-path guard blocks those names everywhere.
    Registry care removes confirmed dead startup/MuiCache values and saves a
    typed recovery journal before every removal.
.NOTES
    Windows PowerShell 5.1. Run elevated (the launcher does it).
#>
param(
    [ValidateSet('Menu','Scan','SelfTest','Library')]
    [string]$Action = 'Menu',
    [switch]$DebugLog,
    [string]$ExpectedUserSid
)

$ErrorActionPreference = 'Stop'
if ($ExpectedUserSid -and [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedUserSid) { throw 'Run Cleaner as an administrator for your own Windows account; a different account would clean and change the wrong user profile.' }
$Script:Version = '1.1.2'
$script:CleanerDebugEnabled = ($Action -ne 'Library' -and ($DebugLog -or $env:WINDOWS_PC_TOOLKIT_DEBUG -eq '1'))
$StateRoot      = Join-Path $env:ProgramData 'WindowsPCToolkit\Cleaner'
$LogRoot        = Join-Path $StateRoot 'Logs'
$RegBackupRoot  = Join-Path $StateRoot 'RegistryBackups'
$FileBackupRoot = Join-Path $StateRoot 'FileBackups'

function Write-CleanerDiagnostic {
    param([string]$Event,[string]$Message)
    if (-not $script:CleanerDebugEnabled) { return }
    try {
        $folder=Join-Path $env:LOCALAPPDATA 'WindowsPCToolkit\Logs'
        [void][IO.Directory]::CreateDirectory($folder)
        $log=Join-Path $folder 'Cleaner_debug.log'
        if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -ge 1MB) { Move-Item -LiteralPath $log -Destination ($log+'.1') -Force }
        Add-Content -LiteralPath $log -Encoding UTF8 -Value ("{0} v{1} {2}: {3}" -f (Get-Date).ToString('o'),$Script:Version,$Event,$Message)
    } catch { Write-Warning ("Could not write cleaner debug log: "+$_.Exception.Message) }
}

# ============================================================================
#  UI + BASIC HELPERS
# ============================================================================

function Write-Status {
    param(
        [ValidateSet('OK','Fail','Warn','Skip','Info','Step')][string]$Type,
        [string]$Text
    )
    $map = @{
        OK   = @{ Tag='  [OK] '; Color='Green' }
        Fail = @{ Tag='  [XX] '; Color='Red' }
        Warn = @{ Tag='  [!!] '; Color='Yellow' }
        Skip = @{ Tag='  [>>] '; Color='DarkCyan' }
        Info = @{ Tag='     ';   Color='Gray' }
        Step = @{ Tag='  [=>] '; Color='Cyan' }
    }
    $m = $map[$Type]
    Write-CleanerDiagnostic $Type $Text
    Write-Host $m.Tag -ForegroundColor $m.Color -NoNewline
    Write-Host $Text -ForegroundColor $(if ($Type -eq 'Info') { 'Gray' } else { 'White' })
}

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Assert-Admin { if (-not (Test-Admin)) { throw 'Run this tool as Administrator.' } }

function Initialize-State {
    foreach ($p in @($StateRoot, $LogRoot, $RegBackupRoot, $FileBackupRoot)) {
        if (-not (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

# ============================================================================
#  PROTECTED-PATH GUARD - the single choke point before every deletion
# ============================================================================

$Script:ProtectedNames = @(
    # browser session / user data
    'Cookies','Login Data','Login Data For Account','Web Data','History','Bookmarks','Favicons',
    'Top Sites','Local Storage','IndexedDB','Session Storage','Sessions','Sync Data',
    'Preferences','Secure Preferences','Local State','Extension State','Extensions','WebCache',
    # user folders
    'Desktop','Documents','Pictures','Videos','Music','Favorites','Contacts','Saved Games',
    'OneDrive','Dropbox','Google Drive',
    '.ollama','.lmstudio','huggingface','torch','whisper','.llama.cpp'
)

function Test-IsProtectedPath {
    param([Parameter(Mandatory)][string]$Path)
    try { $Path=[IO.Path]::GetFullPath($Path) } catch { return $true }
    foreach ($segment in ($Path -split '[\\/]')) {
        if ($Script:ProtectedNames -contains $segment) { return $true }
    }
    return $false
}

function Test-CleanPathWithoutLinks {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $current=[IO.Path]::GetFullPath($Path)
        while ($current) {
            if ((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
            $current=Split-Path $current -Parent
        }
        return $true
    } catch { return $false }
}

function Get-CleanTreeFiles {
    param([string]$Path,[switch]$Report)
    if (-not (Test-CleanPathWithoutLinks $Path) -or (-not $Report -and (Test-IsProtectedPath $Path))) { return }
    $stack=New-Object Collections.Stack; $stack.Push($Path)
    while ($stack.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $stack.Pop() -Force -ErrorAction SilentlyContinue) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (-not $Report -and (Test-IsProtectedPath $item.FullName))) { continue }
            if ($item.PSIsContainer) { $stack.Push($item.FullName) } else { $item }
        }
    }
}

function Assert-NotProtected {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-IsProtectedPath -Path $Path) {
        throw "Refused: '$Path' matches a protected user-data/session name."
    }
}

# ============================================================================
#  CATEGORY TABLE - every row answers "what is this and why is it safe?"
# ============================================================================

function Get-CleanCategories {
    $L = $env:LOCALAPPDATA; $A = $env:APPDATA; $U = $env:USERPROFILE; $W = $env:SystemRoot; $P = $env:ProgramData
    $PF = $env:ProgramFiles; $PF86 = ${env:ProgramFiles(x86)}

    $edgeCaches = @()
    foreach ($n in @('Cache','Code Cache','GPUCache','ShaderCache','GrShaderCache','DawnCache','GraphiteDawnCache','Media Cache','Crashpad\reports')) {
        $edgeCaches += "$L\Microsoft\Edge\User Data\*\$n"
    }
    $chromeCaches = @()
    foreach ($n in @('Cache','Code Cache','GPUCache','ShaderCache','GrShaderCache','DawnCache','GraphiteDawnCache','Media Cache','Crashpad\reports')) {
        $chromeCaches += "$L\Google\Chrome\User Data\*\$n"
    }
    $operaCaches = @()
    foreach ($n in @('Cache','Code Cache','GPUCache','ShaderCache','GrShaderCache','DawnCache','GraphiteDawnCache','System Cache','Media Cache','Crashpad\reports')) {
        $operaCaches += "$A\Opera Software\Opera GX Stable\$n"
    }
    $ffCaches = @(
        "$A\Mozilla\Firefox\Profiles\*\cache2", "$L\Mozilla\Firefox\Profiles\*\cache2",
        "$A\Mozilla\Firefox\Profiles\*\startupCache", "$L\Mozilla\Firefox\Profiles\*\startupCache",
        "$A\Mozilla\Firefox\Profiles\*\shader-cache"
    )
    $pwaCaches = @(
        "$L\Microsoft\Edge\User Data\*\Service Worker\CacheStorage",
        "$L\Google\Chrome\User Data\*\Service Worker\CacheStorage",
        "$A\Opera Software\Opera GX Stable\Service Worker\CacheStorage"
    )
    $gpuCaches = @(
        "$L\NVIDIA\DXCache", "$L\NVIDIA\GLCache", "$L\NVIDIA\ComputeCache",
        "$L\D3DSCache", "$L\AMD\DxCache", "$L\AMD\GLCache", "$L\Intel\ShaderCache"
    )
    $ideCaches = @()
    foreach ($ide in @('Code','Cursor','Windsurf')) {
        foreach ($n in @('Cache','CachedData','Code Cache','GPUCache','logs')) {
            $ideCaches += "$A\$ide\$n"
        }
    }
    $aiCaches = @(
        "$L\Microsoft\Edge\User Data\*\optimization_guide_model_store",
        "$L\Google\Chrome\User Data\*\optimization_guide_model_store",
        "$L\Packages\Microsoft.Copilot_*\LocalCache",
        "$L\Packages\Microsoft.Copilot_*\TempState"
    )

    @(
        [pscustomobject]@{ Id='UserTemp';    Section='System'; Label='User temp files';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=@($env:TEMP);
            Desc='Temporary files left by installers and apps. In-use files are skipped, not forced.' }
        [pscustomobject]@{ Id='WindowsTemp'; Section='System'; Label='Windows temp files';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=@("$W\Temp");
            Desc='System temporary files. Windows recreates anything it still needs.' }
        [pscustomobject]@{ Id='Thumbnails';  Section='System'; Label='Thumbnail and icon caches';
            Risk='SAFE'; Profile='Balanced'; Kind='Files'; Paths=@("$L\Microsoft\Windows\Explorer\thumbcache_*.db","$L\Microsoft\Windows\Explorer\iconcache_*.db");
            Desc='Explorer thumbnail/icon databases. Rebuild automatically; locked ones are skipped.' }
        [pscustomobject]@{ Id='WerQueues';   Section='System'; Label='Error reporting queues';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=@("$P\Microsoft\Windows\WER\ReportArchive","$P\Microsoft\Windows\WER\ReportQueue","$P\Microsoft\Windows\WER\Temp","$L\Microsoft\Windows\WER\ReportArchive","$L\Microsoft\Windows\WER\ReportQueue");
            Desc='Windows Error Reporting queues. Crash reports you already sent or dismissed.' }
        [pscustomobject]@{ Id='CrashDumps';  Section='System'; Label='Crash dumps and minidumps';
            Risk='CAREFUL'; Profile='Strict'; Kind='Files'; Paths=@("$L\CrashDumps\*.dmp","$W\Minidump\*.dmp","$W\MEMORY.DMP");
            Desc='Dumps from app/kernel crashes. Delete unless you are actively debugging a crash.' }
        [pscustomobject]@{ Id='INetCache';   Section='System'; Label='Legacy internet cache';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=@("$L\Microsoft\Windows\INetCache");
            Desc='Old WinINet/IE-era cache. Apps re-download what they need.' }
        [pscustomobject]@{ Id='DeliveryOptimization'; Section='System'; Label='Delivery Optimization cache';
            Risk='SAFE'; Profile='Balanced'; Kind='Special'; Paths=@();
            Desc='Update/Store delivery cache. Removed with the official Windows cmdlet.' }
        [pscustomobject]@{ Id='UpdateLogs';  Section='System'; Label='CBS/DISM servicing logs';
            Risk='CAREFUL'; Profile='Strict'; Kind='Files'; Paths=@("$W\Logs\CBS\*.log","$W\Logs\DISM\*.log");
            Desc='Component-servicing logs. Locked logs (during a scan) are skipped.' }
        [pscustomobject]@{ Id='EdgeCaches';   Section='Browsers'; Label='Edge caches';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=$edgeCaches;
            Desc='Page/GPU caches only. Cookies, logins, history and bookmarks are never touched.' }
        [pscustomobject]@{ Id='ChromeCaches'; Section='Browsers'; Label='Chrome caches';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=$chromeCaches;
            Desc='Page/GPU caches only. Cookies, logins, history and bookmarks are never touched.' }
        [pscustomobject]@{ Id='OperaGxCaches'; Section='Browsers'; Label='Opera GX caches';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=$operaCaches;
            Desc='Page/GPU/system caches only. You stay logged in everywhere.' }
        [pscustomobject]@{ Id='FirefoxCaches'; Section='Browsers'; Label='Firefox caches';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=$ffCaches;
            Desc='cache2/startup cache only. Cookies, logins, history and bookmarks are never touched.' }
        [pscustomobject]@{ Id='GpuCaches';   Section='Graphics'; Label='GPU shader caches';
            Risk='CAREFUL'; Profile='Strict'; Kind='Children'; Paths=$gpuCaches;
            Desc='Compiled shader caches (NVIDIA/AMD/Intel/D3D). First launch of a game may stutter while they rebuild.' }
        [pscustomobject]@{ Id='IdeCaches';   Section='AI & Dev'; Label='VS Code / Cursor / Windsurf caches';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=$ideCaches;
            Desc='Editor caches and logs. Settings, extensions and history are not touched.' }
        [pscustomobject]@{ Id='AiAppCaches'; Section='AI & Dev'; Label='AI assistant model caches';
            Risk='KEEP'; Profile='Report'; Kind='Report'; Paths=$aiCaches;
            Desc='Edge/Chrome AI model stores and Copilot app caches. Re-downloaded on demand.' }
        [pscustomobject]@{ Id='BakFiles';    Section='Files'; Label='Patcher leftover backups (.bak/.old/.tmp/.orig)';
            Risk='KEEP'; Profile='Report'; Kind='Special'; Paths=@();
            Desc='Backup review only. A surviving original does not prove a backup is disposable; no profile deletes these.' }

        [pscustomobject]@{ Id='WUCache';     Section='System'; Label='Windows Update download cache';
            Risk='KEEP'; Profile='Report'; Kind='Report'; Paths=@("$W\SoftwareDistribution\Download");
            Desc='Update downloads. Partial/stopped downloads re-download; in-progress ones are locked and skipped.' }
        [pscustomobject]@{ Id='Prefetch';    Section='System'; Label='Prefetch app-launch cache';
            Risk='CAREFUL'; Profile='Strict'; Kind='Children'; Paths=@("$W\Prefetch");
            Desc='App launch accelerator. Windows rebuilds it; first launches get slightly slower.' }
        [pscustomobject]@{ Id='PwaCaches';   Section='Browsers'; Label='PWA/service-worker caches';
            Risk='CAREFUL'; Profile='Strict'; Kind='Children'; Paths=$pwaCaches;
            Desc='Offline caches for installed web apps. Offline copies rebuild on next online visit.' }
        [pscustomobject]@{ Id='RecallData';  Section='AI & Dev'; Label='Windows Recall snapshots';
            Risk='KEEP'; Profile='Report'; Kind='Report'; Paths=@("$L\CoreAIPlatform.00");
            Desc='Your searchable Recall screen history. Deleting this erases that history permanently.' }
        [pscustomobject]@{ Id='WindowsOld';  Section='System'; Label='Previous Windows installation (Windows.old)';
            Risk='KEEP'; Profile='Report'; Kind='Report'; Paths=@("$env:SystemDrive\Windows.old");
            Desc='Previous Windows installation, kept for rollback. Use Windows Storage settings to review removal.' }
    )
}

function Get-ReportCategories {
    $U = $env:USERPROFILE
    @(
        [pscustomobject]@{ Id='ModelStores'; Section='AI & Dev'; Label='AI model stores (never deleted)';
            Risk='REPORT'; Profile='Report'; Kind='Report'; Paths=@(
                "$U\.lmstudio\models", "$U\.ollama\models", "$U\.cache\huggingface",
                "$U\.cache\torch", "$U\.cache\whisper", "$U\.llama.cpp"
            );
            Desc='Models and caches you own. Shown with size so you can decide - this tool will never delete them.' }
    )
}

# ============================================================================
#  MEASURE + CLEAN ENGINE
# ============================================================================

function Resolve-CategoryDirs {
    param($Category)
    $out = @()
    foreach ($p in $Category.Paths) {
        if ($p -match '\*') {
            $out += @(Get-Item -Path ([WildcardPattern]::Escape($p).Replace('`*','*')) -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer })
        } elseif (Test-Path -LiteralPath $p -PathType Container -ErrorAction SilentlyContinue) {
            $out += Get-Item -LiteralPath $p -Force
        }
    }
    return @($out)
}

function Resolve-CategoryFiles {
    param($Category)
    $out = @()
    foreach ($p in $Category.Paths) {
        if ($p -match '\*') {
            $out += @(Get-ChildItem -Path ([WildcardPattern]::Escape($p).Replace('`*','*')) -Force -File -ErrorAction SilentlyContinue)
        } elseif (Test-Path -LiteralPath $p -PathType Leaf -ErrorAction SilentlyContinue) {
            $out += Get-Item -LiteralPath $p -Force
        }
    }
    return @($out)
}

function Measure-Category {
    param($Category)
    $bytes = [long]0; $files = 0
    switch ($Category.Kind) {
        'Children' {
            foreach ($dir in Resolve-CategoryDirs -Category $Category) {
                $items = if ($Category.Id -in @('UserTemp','WindowsTemp')) { @(Get-DisposableTempFiles @($dir.FullName)) } else { @(Get-CleanTreeFiles $dir.FullName) }
                $files += $items.Count
                $bytes += [long](($items | Measure-Object -Property Length -Sum).Sum)
            }
        }
        'Files' {
            foreach ($f in Resolve-CategoryFiles -Category $Category) {
                if ((Test-CleanPathWithoutLinks $f.FullName) -and -not (Test-IsProtectedPath $f.FullName)) { $files++; $bytes += $f.Length }
            }
        }
        'Report' {
            foreach ($dir in Resolve-CategoryDirs -Category $Category) {
                $items = @(Get-CleanTreeFiles $dir.FullName -Report)
                $files += $items.Count
                $bytes += [long](($items | Measure-Object -Property Length -Sum).Sum)
            }
        }
        'Special' {
            switch ($Category.Id) {
                'DeliveryOptimization' {
                    $p = Join-Path $env:SystemRoot 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization'
                    if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
                        $items = @(Get-CleanTreeFiles $p)
                        $files += $items.Count
                        $bytes += [long](($items | Measure-Object -Property Length -Sum).Sum)
                    }
                }
                'BakFiles' {
                    $r = Get-BakCandidates
                    $files += @($r.Deletable).Count + @($r.Orphans).Count
                    foreach ($f in @($r.Deletable)+@($r.Orphans)) { $bytes += $f.Length }
                }
            }
        }
    }
    return [pscustomobject]@{ Bytes = $bytes; Files = $files }
}

function Remove-ItemSafe {
    # Returns $true when removed, $false when skipped (locked / protected / denied).
    param([string]$Path, [switch]$Directory)
    if (Test-IsProtectedPath -Path $Path) { return $false }
    try {
        $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not (Test-CleanPathWithoutLinks $item.FullName)) { return $false }
        if ($Directory) {
            $stack=New-Object Collections.Stack; $stack.Push($Path)
            while ($stack.Count) {
                foreach ($child in Get-ChildItem -LiteralPath $stack.Pop() -Force -ErrorAction Stop) {
                    if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Test-IsProtectedPath $child.FullName)) { return $false }
                    if ($child.PSIsContainer) { $stack.Push($child.FullName) }
                }
            }
        }
        if ($Directory) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
        else            { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
        return $true
    } catch { Write-CleanerDiagnostic 'RemovalFailure' ("$Path : "+$_.Exception.Message); return $false }
}

function Get-BakCandidates {
    param([string[]]$Roots, [int]$MaxDepth = 5)
    if (-not $Roots) {
        $Roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, $env:APPDATA,
                   (Join-Path $env:USERPROFILE 'Downloads'))
    }
    $exts = @('.bak', '.old', '.tmp', '.orig')
    $deletable = New-Object System.Collections.ArrayList
    $orphans   = New-Object System.Collections.ArrayList
    foreach ($root in $Roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container -ErrorAction SilentlyContinue) -or -not (Test-CleanPathWithoutLinks $root)) { continue }
        $stack = New-Object System.Collections.Stack
        $stack.Push([pscustomobject]@{ Path = $root; Depth = 0 })
        while ($stack.Count -gt 0) {
            $cur = $stack.Pop()
            if ($cur.Depth -gt $MaxDepth) { continue }
            if (Test-IsProtectedPath -Path $cur.Path) { continue }
            foreach ($d in @(Get-ChildItem -LiteralPath $cur.Path -Directory -Force -ErrorAction SilentlyContinue |
                             Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
                $stack.Push([pscustomobject]@{ Path = $d.FullName; Depth = $cur.Depth + 1 })
            }
            foreach ($f in @(Get-ChildItem -LiteralPath $cur.Path -File -Force -ErrorAction SilentlyContinue)) {
                if (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Test-IsProtectedPath $f.FullName)) { continue }
                if ($exts -notcontains $f.Extension.ToLowerInvariant()) { continue }
                $original = Join-Path $cur.Path ([IO.Path]::GetFileNameWithoutExtension($f.Name))
                if (Test-Path -LiteralPath $original -PathType Leaf -ErrorAction SilentlyContinue) { [void]$deletable.Add($f) }
                else { [void]$orphans.Add($f) }
            }
        }
    }
    return [pscustomobject]@{ Deletable = @($deletable); Orphans = @($orphans) }
}

function Invoke-CleanCategory {
    param($Category)
    $result = [pscustomobject]@{ Id = $Category.Id; Label = $Category.Label; Removed = 0; Skipped = 0; Bytes = [long]0; Note = ''; Status='Completed' }
    if ($Category.Profile -eq 'Report' -or $Category.Kind -eq 'Report' -or $Category.Id -in @('WindowsOld','BakFiles','WUCache','RecallData','AiAppCaches','ModelStores')) { $result.Status='Skipped'; $result.Note='Review only; kept all files.'; return $result }
    switch ($Category.Kind) {
        'Children' {
            foreach ($dir in Resolve-CategoryDirs -Category $Category) {
                if ((Test-IsProtectedPath $dir.FullName) -or -not (Test-CleanPathWithoutLinks $dir.FullName)) { $result.Skipped++; continue }
                if ($Category.Id -in @('UserTemp','WindowsTemp')) {
                    foreach ($file in Get-DisposableTempFiles -Roots @($dir.FullName)) {
                        $current=Get-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                        if (-not $current -or $current.LastWriteTime -ge (Get-Date).AddDays(-7) -or $current.LastAccessTime -ge (Get-Date).AddDays(-7)) { $result.Skipped++; continue }
                        if (Remove-ItemSafe $file.FullName) { $result.Removed++; $result.Bytes+=$file.Length }
                        else { $result.Skipped++ }
                    }
                    continue
                }
                foreach ($child in @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue)) {
                    if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { $result.Skipped++; continue }
                    $size = if ($child.PSIsContainer) {
                        [long](@(Get-CleanTreeFiles $child.FullName | Measure-Object -Property Length -Sum).Sum)
                    } else { [long]$child.Length }
                    if (Remove-ItemSafe -Path $child.FullName -Directory:$child.PSIsContainer) {
                        $result.Removed++
                        $result.Bytes += $size
                    } else { $result.Skipped++ }
                }
            }
        }
        'Files' {
            foreach ($f in Resolve-CategoryFiles -Category $Category) {
                if (Remove-ItemSafe -Path $f.FullName) { $result.Removed++; $result.Bytes += [long]$f.Length }
                else { $result.Skipped++ }
            }
        }
        'Special' {
            switch ($Category.Id) {
                'DeliveryOptimization' {
                    if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
                        try {
                            $before = Measure-Category -Category $Category
                            Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
                            $after = Measure-Category -Category $Category
                            $result.Removed = [math]::Max(0,$before.Files-$after.Files); $result.Bytes = [math]::Max(0,$before.Bytes-$after.Bytes)
                            $result.Note = 'Measured cache reduction after Windows cleanup; pinned/in-use files may remain.'
                        } catch { $result.Status='Failed'; $result.Note = $_.Exception.Message; Write-CleanerDiagnostic 'CleanupFailure' $result.Note }
                    } else { $result.Status='Skipped'; $result.Note = 'cmdlet not available on this build' }
                }
            }
        }
    }
    return $result
}

# ============================================================================
#  REGISTRY CARE
# ============================================================================

function Get-CommandTargetPath {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($c.StartsWith('"')) {
        $end = $c.IndexOf('"', 1)
        if ($end -gt 1) { $c = $c.Substring(1, $end - 1) } else { return $null }
    } else {
        $m = [regex]::Match($c, '^(.*?\.exe)(\s|$)', 'IgnoreCase')
        if ($m.Success) { $c = $m.Groups[1].Value } else { $c = ($c -split '\s+')[0] }
        # Unquoted paths with spaces have several CreateProcess candidates.
        if ($c -match '\s' -or $CommandLine -match '^\s*[^"\s]+\.exe\s+[^-"/]*\\') { return $null }
    }
    if (-not [IO.Path]::IsPathRooted($c)) { return $null }
    return $c
}

function Get-DisposableTempFiles {
    param([string[]]$Roots,[int]$Days=7)
    $cutoff=(Get-Date).AddDays(-[math]::Max(7,$Days))
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $rootItem=Get-Item -LiteralPath $root -Force -ErrorAction Stop
        if ((Test-IsProtectedPath $rootItem.FullName) -or -not (Test-CleanPathWithoutLinks $rootItem.FullName)) { continue }
        $stack=New-Object Collections.Stack; $stack.Push($rootItem.FullName)
        while ($stack.Count) {
            foreach ($item in Get-ChildItem -LiteralPath $stack.Pop() -Force -ErrorAction SilentlyContinue) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Test-IsProtectedPath $item.FullName)) { continue }
                if ($item.PSIsContainer) { $stack.Push($item.FullName) }
                elseif ($item.LastWriteTime -lt $cutoff -and $item.LastAccessTime -lt $cutoff) { $item }
            }
        }
    }
}

function Get-RegistryIssues {
    $issues = New-Object System.Collections.ArrayList

    # 1) Orphaned uninstall entries (uninstaller target is gone)
    foreach ($root in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try {
                $props = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                if ($props.PSObject.Properties.Name -contains 'SystemComponent' -and $props.SystemComponent -eq 1) { continue }
                if ($props.PSObject.Properties.Name -notcontains 'UninstallString') { continue }
                $target = Get-CommandTargetPath ([string]$props.UninstallString)
                if ($target -and -not (Test-Path -LiteralPath $target -ErrorAction SilentlyContinue)) {
                    [void]$issues.Add([pscustomobject]@{
                        Category = 'Missing uninstallers (review only)'; Kind = 'Review'
                        Key = $k.PSPath; Name = $k.PSChildName
                        Display = $k.PSChildName; Evidence = "missing: $target"
                    })
                }
            } catch { }
        }
    }

    # 2) Dead startup (Run/RunOnce) values
    foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce')) {
        try {
            $props = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -in @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')) { continue }
                $target = Get-CommandTargetPath ([string]$prop.Value)
                if ($target -and -not (Test-Path -LiteralPath $target -ErrorAction SilentlyContinue)) {
                    [void]$issues.Add([pscustomobject]@{
                        Category = 'Dead startup entries'; Kind = 'Value'
                        Key = $key; Name = $prop.Name
                        Display = [string]$prop.Value; Evidence = "missing: $target"
                    })
                }
            }
        } catch { }
    }

    # 3) Stale App Paths (default value target is gone)
    foreach ($root in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths')) {
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try {
                $target = [string](Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop).'(default)'
                $target = [Environment]::ExpandEnvironmentVariables($target.Trim('"'))
                if ($target -and [IO.Path]::IsPathRooted($target) -and -not (Test-Path -LiteralPath $target -ErrorAction SilentlyContinue)) {
                    [void]$issues.Add([pscustomobject]@{
                        Category = 'Stale App Paths (review only)'; Kind = 'Review'
                        Key = $k.PSPath; Name = $k.PSChildName
                        Display = $k.PSChildName; Evidence = "missing: $target"
                    })
                }
            } catch { }
        }
    }

    # 4) Stale MuiCache entries (named after a missing exe)
    $mui = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
    try {
        $props = Get-ItemProperty -LiteralPath $mui -ErrorAction Stop
        foreach ($prop in $props.PSObject.Properties) {
            if ($prop.Name -in @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')) { continue }
            $pathPart = $prop.Name -replace '\.(FriendlyAppName|ApplicationCompany|NoRemove)$', ''
            if ($pathPart -notmatch '\\') { continue }
            $pathPart = [Environment]::ExpandEnvironmentVariables($pathPart)
            if ([IO.Path]::IsPathRooted($pathPart) -and -not (Test-Path -LiteralPath $pathPart -ErrorAction SilentlyContinue)) {
                [void]$issues.Add([pscustomobject]@{
                    Category = 'Stale MuiCache entries'; Kind = 'Value'
                    Key = $mui; Name = $prop.Name
                    Display = $pathPart; Evidence = 'app no longer exists'
                })
            }
        }
    } catch { }

    # 5) Dead Startup-folder shortcuts
    $sh = $null
    try {
        $sh = New-Object -ComObject WScript.Shell
        foreach ($dir in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
            foreach ($lnk in @(Get-ChildItem -LiteralPath $dir -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
                try {
                    $target = [Environment]::ExpandEnvironmentVariables($sh.CreateShortcut($lnk.FullName).TargetPath)
                    if ($target -and [IO.Path]::IsPathRooted($target) -and -not (Test-Path -LiteralPath $target -ErrorAction SilentlyContinue)) {
                        [void]$issues.Add([pscustomobject]@{
                            Category = 'Dead startup shortcuts'; Kind = 'File'
                            Key = $lnk.FullName; Name = $lnk.Name
                            Display = $lnk.Name; Evidence = "missing: $target"
                        })
                    }
                } catch { }
            }
        }
    } catch { } finally { if ($sh) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) } }

    return @($issues)
}

function Invoke-RegistryCare {
    Assert-Admin
    Import-Module (Join-Path $PSScriptRoot '..\Modules\Toolkit.Core.psm1') -Force -DisableNameChecking
    $issues=@(Get-RegistryIssues | Sort-Object Category,Display)
    if (-not $issues.Count) { Write-Status OK 'No registry review candidates found.'; return }
    for ($i=0; $i -lt $issues.Count; $i++) {
        Write-Host ("  [{0}] {1}: {2} ({3})" -f ($i+1),$issues[$i].Category,$issues[$i].Display,$issues[$i].Evidence)
    }
    Write-Status Info 'Maintenance can remove verified dead startup and MuiCache values. Missing uninstallers, app registrations and shortcuts are retained for review.'
    $pick=Read-Host '  Repair [A]ll eligible values, comma-separated numbers, or 0 to cancel'
    if ($pick -eq '0' -or [string]::IsNullOrWhiteSpace($pick)) { return }
    $selected=@()
    if ($pick -match '^[Aa]$') { $selected=$issues }
    else {
        foreach ($part in $pick -split ',') {
            $index=0
            if ([int]::TryParse($part.Trim(),[ref]$index) -and $index -gt 0 -and $index -le $issues.Count) { $selected+=$issues[$index-1] }
        }
    }
    if (-not $selected.Count) { return }
    $lock=Enter-SuiteOperation
    try {
        $run=New-SuiteRun 'RegistryCare'
        foreach ($issue in $selected) {
            $start=$run.Registry.Count
            try {
                $target=$issue.Display
                if ($issue.Category -eq 'Dead startup entries') {
                    $current=Get-Item -LiteralPath $issue.Key -ErrorAction Stop
                    $target=if ($current.GetValueNames() -contains $issue.Name) { Get-CommandTargetPath ([string]$current.GetValue($issue.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)) } else { $null }
                }
                if ($issue.Kind -ne 'Value' -or $issue.Category -notin @('Dead startup entries','Stale MuiCache entries') -or -not (Test-SuiteMissingExecutable $target)) {
                    Add-SuiteStep $run $issue.Display 'Skipped' 'Review candidate retained. No registry key/app registration/shortcut removed.'
                    continue
                }
                Set-SuiteRegistry $run $issue.Key $issue.Name $null -Remove
                Add-SuiteStep $run $issue.Name 'Applied' 'Dead value removed with exact typed-value backup.'
            } catch {
                $message=$_.Exception.Message
                for ($index=$run.Registry.Count-1; $index -ge $start; $index--) {
                    try { Undo-SuiteRegistryEntry $run.Registry[$index] } catch { $message+=' Rollback: '+$_.Exception.Message }
                }
                Add-SuiteStep $run $issue.Name 'Failed' $message
            }
        }
        $run.Status=if (@($run.Steps | Where-Object Status -eq 'Failed').Count) { 'CompletedWithErrors' } else { 'Completed' }
        Save-SuiteJson $run.Path $run
        $run.Steps | Format-Table Action,Status,Message -Wrap
        Write-Status Info ("Recovery report: {0}" -f $run.Path)
    } finally { $lock.ReleaseMutex(); $lock.Dispose() }
}
function Restore-LatestRegistryBackup {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\Toolkit.Core.psm1') -Force -DisableNameChecking
    $care=Get-SuiteHistory | Where-Object Mode -eq 'RegistryCare' | Select-Object -First 1
    if ($care) { $undo=Invoke-SuiteUndo $care.Path; Write-Status Info $undo.Message; return }
    Assert-Admin
    if(-not(Test-Path -LiteralPath $RegBackupRoot -ErrorAction Stop)){Write-Status Warn 'No registry backups exist yet.';return}
    if(-not(Test-CleanPathWithoutLinks $RegBackupRoot)){Write-Status Warn 'Legacy backup folder contains a link or cannot be inspected; automatic recovery refused.';return}
    $latest = Get-ChildItem -LiteralPath $RegBackupRoot -Directory -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { Write-Status Warn 'No registry backups exist yet.'; return }
    if(-not(Test-CleanPathWithoutLinks $latest.FullName)){Write-Status Warn 'Latest legacy backup contains a link or cannot be inspected; automatic recovery refused.';return}
    Write-Status Warn 'Legacy manifests do not record a verifiable computer, user or restore scope; automatic file copying and whole-key registry imports are retired.'
    Write-Status Info ("Backups are preserved at {0}. Review the manifest and backup contents for manual recovery. Current Registry Care reports use exact typed-value undo." -f $latest.FullName)
}

# ============================================================================
#  SCAN REPORT + PROFILES
# ============================================================================

function Show-ScanLine {
    param($Category, $Info, [string]$Prefix = '')
    $tag = switch ($Category.Risk) {
        'SAFE'    { '[SAFE]   ' } 'CAREFUL' { '[CAREFUL]' }
        'STRICT'  { '[STRICT] ' } 'REPORT'  { '[KEEP]   ' } 'KEEP' { '[KEEP]   ' }
        default   { '[----]   ' }
    }
    $color = switch ($Category.Risk) { 'SAFE' { 'Green' } 'CAREFUL' { 'Yellow' } 'STRICT' { 'Red' } default { 'DarkCyan' } }
    Write-Host ("  $Prefix{0} {1,12}  {2,7} files  " -f $tag, (Format-Size $Info.Bytes), $Info.Files) -ForegroundColor $color -NoNewline
    Write-Host $Category.Label
    Write-Host ("           {0}" -f $Category.Desc) -ForegroundColor DarkGray
}

function Show-ScanReport {
    $cats = Get-CleanCategories
    $rep  = @(Get-ReportCategories) + @($cats | Where-Object Profile -eq 'Report')
    Write-Host ''
    Write-Status Step 'Scanning (read-only - nothing is deleted by a scan)...'
    $measured = @{}
    $balBytes = [long]0; $balCats = 0
    $strBytes = [long]0; $strCats = 0
    $repBytes = [long]0
    foreach ($c in $cats) {
        $m = Measure-Category -Category $c
        $measured[$c.Id] = $m
        if ($m.Bytes -gt 0 -or $m.Files -gt 0) {
            if ($c.Profile -eq 'Balanced') { $balBytes += $m.Bytes; if ($m.Bytes -gt 0) { $balCats++ } }
            elseif ($c.Profile -eq 'Strict') { $strBytes += $m.Bytes; if ($m.Bytes -gt 0) { $strCats++ } }
        }
    }
    foreach ($c in $rep) {
        $m = Measure-Category -Category $c
        $measured[$c.Id] = $m
        $repBytes += $m.Bytes
    }

    Write-Host ''
    Write-Host '  BALANCED PROFILE (safe - recommended)' -ForegroundColor Cyan
    foreach ($c in $cats | Where-Object { $_.Profile -eq 'Balanced' }) { Show-ScanLine -Category $c -Info $measured[$c.Id] }
    Write-Host ''
    Write-Host '  STRICT PROFILE (opt-in - read each description)' -ForegroundColor Yellow
    foreach ($c in $cats | Where-Object { $_.Profile -eq 'Strict' }) { Show-ScanLine -Category $c -Info $measured[$c.Id] }
    Write-Host ''
    Write-Host '  NOT DELETED BY THIS TOOL (shown so you can decide yourself)' -ForegroundColor DarkCyan
    foreach ($c in $rep) { Show-ScanLine -Category $c -Info $measured[$c.Id] }
    Write-Host ''
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Status Info ("Balanced would free: {0} ({1} categories with content)" -f (Format-Size $balBytes), $balCats)
    Write-Status Info ("Strict adds:         {0} ({1} categories with content)" -f (Format-Size $strBytes), $strCats)
    Write-Status Info ("Kept (models/user data): {0}" -f (Format-Size $repBytes))
    return $measured
}

function Get-FreeSpaceBytes {
    $d = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $env:SystemDrive) -ErrorAction SilentlyContinue
    if ($d) { return [long]$d.FreeSpace }
    return 0
}

function Save-RunLog {
    param([string]$Name, $Results, [long]$FreeBefore, [long]$FreeAfter)
    Initialize-State
    $path = Join-Path $LogRoot ("clean_{0}_{1}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss'),[guid]::NewGuid().ToString('N'))
    $obj = [pscustomobject]@{
        Tool = 'PC Cleaner'; Version = $Script:Version; Profile = $Name
        Created = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME
        FreeBeforeBytes = $FreeBefore; FreeAfterBytes = $FreeAfter
        TotalRemovedBytes = [long](($Results | Measure-Object -Property Bytes -Sum).Sum)
        Status = $(if (@($Results | Where-Object Status -eq 'Failed').Count) { 'CompletedWithErrors' } else { 'Completed' })
        Categories = @($Results)
    }
    ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-Profile {
    param([ValidateSet('Balanced','Strict')][string]$Name)
    Assert-Admin; Initialize-State
    $cats = @(Get-CleanCategories | Where-Object { $_.Profile -eq $Name -or ($Name -eq 'Strict' -and $_.Profile -eq 'Balanced') })
    Write-Host ''
    Write-Status Step ("Running {0} clean ({1} categories)..." -f $Name, $cats.Count)
    Write-Status Info 'Locked/in-use files are skipped and counted, never forced.'
    $confirm = Read-Host ("  Delete the {0}-profile content now? (y/N)" -f $Name)
    if ($confirm -notmatch '^[Yy]$') { Write-Status Skip 'Cancelled - nothing was deleted.'; return }

    $freeBefore = Get-FreeSpaceBytes
    $results = New-Object System.Collections.ArrayList
    foreach ($c in $cats) {
        $r = Invoke-CleanCategory -Category $c
        [void]$results.Add($r)
        Write-Status $(if ($r.Status -eq 'Failed') { 'Fail' } elseif ($r.Status -eq 'Skipped') { 'Skip' } else { 'OK' }) ("{0}: removed {1} item(s), freed {2}{3}" -f $c.Label, $r.Removed, (Format-Size $r.Bytes),
            $(if ($r.Skipped -gt 0) { " ($($r.Skipped) locked/in-use skipped)" } else { '' }))
        if ($r.Note) { Write-Status Info ("   {0}" -f $r.Note) }
    }
    $freeAfter = Get-FreeSpaceBytes
    $log = Save-RunLog -Name $Name -Results $results -FreeBefore $freeBefore -FreeAfter $freeAfter
    $totalBytes = [long](($results | Measure-Object -Property Bytes -Sum).Sum)
    $totalRemoved = [int](($results | Measure-Object -Property Removed -Sum).Sum)
    $totalSkipped = [int](($results | Measure-Object -Property Skipped -Sum).Sum)
    Write-Host ''
    Write-Host ("  ============================================================") -ForegroundColor DarkCyan
    Write-Status $(if (@($results | Where-Object Status -eq 'Failed').Count) { 'Warn' } else { 'OK' }) ("{0} clean complete: {1} item(s) removed, {2} skipped, {3} freed. {4} category failure(s)." -f $Name, $totalRemoved, $totalSkipped, (Format-Size $totalBytes),@($results | Where-Object Status -eq 'Failed').Count)
    Write-Status Info ("Disk free: {0} -> {1}" -f (Format-Size $freeBefore), (Format-Size $freeAfter))
    Write-Status Info ("Log: {0}" -f $log)
}

function Invoke-PickCategories {
    Assert-Admin
    $cats = @(Get-CleanCategories)
    Write-Host ''
    for ($i = 0; $i -lt $cats.Count; $i++) {
        $c = $cats[$i]
        Write-Host ("  [{0,2}] {1,-12} {2,-38} {3}" -f ($i + 1), "[$($c.Risk)]", $c.Label, $c.Desc) -ForegroundColor Gray
    }
    $pick = Read-Host '  Categories to clean (e.g. 1,3,5-7) or 0 to cancel'
    if ($pick -eq '0' -or [string]::IsNullOrWhiteSpace($pick)) { return }
    $selected = @()
    foreach ($part in ($pick -split ',')) {
        $first=0; $last=0
        if ($part -match '^\s*(\d+)\s*-\s*(\d+)\s*$') {
            if ([int]::TryParse($Matches[1],[ref]$first) -and [int]::TryParse($Matches[2],[ref]$last) -and $first -ge 1 -and $first -le $cats.Count -and $last -ge 1 -and $last -le $cats.Count) {
                foreach ($n in $first..$last) { $selected += $cats[$n-1] }
            }
        } elseif ([int]::TryParse($part.Trim(),[ref]$first) -and $first -ge 1 -and $first -le $cats.Count) { $selected += $cats[$first-1] }
    }
    $selected = @($selected | Where-Object { $_ } | Select-Object -Unique)
    if (@($selected).Count -eq 0) { Write-Status Skip 'Nothing valid selected.'; return }
    Write-Status Info ("Selected: {0}" -f (($selected | ForEach-Object { $_.Label }) -join ', '))
    $confirm = Read-Host '  Delete the selected categories now? (y/N)'
    if ($confirm -notmatch '^[Yy]$') { Write-Status Skip 'Cancelled.'; return }
    $freeBefore = Get-FreeSpaceBytes
    $results = New-Object System.Collections.ArrayList
    foreach ($c in $selected) {
        $r = Invoke-CleanCategory -Category $c
        [void]$results.Add($r)
        Write-Status $(if ($r.Status -eq 'Failed') { 'Fail' } elseif ($r.Status -eq 'Skipped') { 'Skip' } else { 'OK' }) ("{0}: removed {1} item(s), freed {2}{3}" -f $c.Label, $r.Removed, (Format-Size $r.Bytes),
            $(if ($r.Skipped -gt 0) { " ($($r.Skipped) locked/in-use skipped)" } else { '' }))
        if ($r.Note) { Write-Status Info $r.Note }
    }
    $log = Save-RunLog -Name 'Custom' -Results $results -FreeBefore $freeBefore -FreeAfter (Get-FreeSpaceBytes)
    Write-Status $(if (@($results | Where-Object Status -eq 'Failed').Count) { 'Warn' } else { 'OK' }) ("Custom clean complete. Log: {0}" -f $log)
}

function Invoke-RecycleBin {
    Assert-Admin
    $confirm = Read-Host '  Empty the Recycle Bin? This cannot be undone. (y/N)'
    if ($confirm -notmatch '^[Yy]$') { Write-Status Skip 'Recycle Bin kept.'; return }
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Status OK 'Recycle Bin emptied.'
    } catch { Write-Status Warn 'Recycle Bin already empty or inaccessible.' }
}

# ============================================================================
#  SELF-TEST - the two rules that protect user data
# ============================================================================

function Invoke-SelfTest {
    $t = Join-Path $env:TEMP ('pccleaner_selftest_' + (Get-Random))
    $fails = New-Object System.Collections.ArrayList
    function Check([bool]$Cond, [string]$Msg) { if (-not $Cond) { [void]$fails.Add($Msg) } }
    try {
        New-Item -ItemType Directory -Path $t -Force | Out-Null

        # guard: protected names must be refused
        foreach ($n in @('Cookies', 'Login Data', 'History', 'Documents')) {
            $blocked = $false
            try { Assert-NotProtected -Path (Join-Path $t $n) } catch { $blocked = $true }
            Check $blocked "guard did NOT block protected name: $n"
        }
        # guard: cache names must be allowed
        foreach ($n in @('Cache', 'Code Cache', 'GPUCache', 'Temp')) {
            $allowed = $true
            try { Assert-NotProtected -Path (Join-Path $t $n) } catch { $allowed = $false }
            Check $allowed "guard wrongly blocked: $n"
        }
        # bak rule: sibling present -> deletable; orphan -> kept
        'orig' | Set-Content -LiteralPath (Join-Path $t 'app.dll')
        'backup' | Set-Content -LiteralPath (Join-Path $t 'app.dll.bak')
        'orphan' | Set-Content -LiteralPath (Join-Path $t 'gone.dll.bak')
        $r = Get-BakCandidates -Roots @($t)
        $names = @($r.Deletable | ForEach-Object { $_.Name })
        $orphanNames = @($r.Orphans | ForEach-Object { $_.Name })
        Check ($names -contains 'app.dll.bak') 'bak rule: sibling-verified file not offered for deletion'
        Check ($orphanNames -contains 'gone.dll.bak') 'bak rule: orphan file not protected'
        Check ($names -notcontains 'gone.dll.bak') 'bak rule: orphan file offered for deletion'
    } finally {
        Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($fails.Count -gt 0) {
        Write-Host 'SELF-TEST FAILED:' -ForegroundColor Red
        $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host 'SELF-TEST PASSED (guard + bak rule)' -ForegroundColor Green
    exit 0
}

# ============================================================================
#  MENU / ENTRY
# ============================================================================

function Show-Menu {
    Clear-Host
    Write-Host '  ================================================================' -ForegroundColor DarkCyan
    Write-Host ('  PC CLEANER  v{0}' -f $Script:Version) -ForegroundColor Yellow
    Write-Host '  Scan first. Delete second. User data never.' -ForegroundColor Gray
    Write-Host '  ================================================================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  [1] Scan (read-only report - start here)' -ForegroundColor Cyan
    Write-Host '  [2] Balanced clean (recommended)' -ForegroundColor Green
    Write-Host '  [3] Strict clean (adds CAREFUL/STRICT categories)'
    Write-Host '  [4] Clean specific categories'
    Write-Host '  [5] Registry Care (orphaned entries; backups included)' -ForegroundColor Cyan
    Write-Host '  [6] Empty the Recycle Bin'
    Write-Host '  [7] Restore latest registry backup' -ForegroundColor Yellow
    Write-Host '  [0] Exit'
    Write-Host ''
}

if ($Action -eq 'Library') { return }
Write-CleanerDiagnostic 'Startup' ("Action=$Action; StateRoot=$StateRoot; LogRoot=$LogRoot; Temp=$env:TEMP")
switch ($Action) {
    'SelfTest' { Invoke-SelfTest }
    'Scan'     { Initialize-State; Show-ScanReport | Out-Null; exit 0 }
    default {
        Initialize-State
        while ($true) {
            Show-Menu
            $choice = (Read-Host '  Select').Trim()
            try {
                switch ($choice) {
                    '1' { Show-ScanReport | Out-Null; Write-Host ''; Read-Host '  Press Enter to continue' | Out-Null }
                    '2' { Invoke-Profile -Name Balanced; Read-Host '  Press Enter to continue' | Out-Null }
                    '3' { Invoke-Profile -Name Strict; Read-Host '  Press Enter to continue' | Out-Null }
                    '4' { Invoke-PickCategories; Read-Host '  Press Enter to continue' | Out-Null }
                    '5' { Invoke-RegistryCare; Read-Host '  Press Enter to continue' | Out-Null }
                    '6' { Invoke-RecycleBin; Read-Host '  Press Enter to continue' | Out-Null }
                    '7' { Restore-LatestRegistryBackup; Read-Host '  Press Enter to continue' | Out-Null }
                    '0' { exit 0 }
                    default { Write-Status Warn 'Invalid selection.' }
                }
            } catch { Write-CleanerDiagnostic 'Exception' ($_.Exception.ToString()+"`n"+$_.ScriptStackTrace); Write-Status Fail $_.Exception.Message }
        }
    }
}
