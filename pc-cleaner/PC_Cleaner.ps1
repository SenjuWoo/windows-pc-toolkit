#requires -version 5.1
<#
.SYNOPSIS
    PC Cleaner v1.0.0 - scan-first disk cleanup and registry care for Windows 10/11.
.DESCRIPTION
    Every category is labeled with what it is and why it is safe. Nothing is
    deleted without an explicit profile/pick and a confirmation. User data -
    documents, browser cookies/logins/history, app state, AI model stores - is
    never deleted: one protected-path guard blocks those names everywhere.
    Registry care only removes entries that are provably orphaned and exports a
    .reg backup before every removal.
.NOTES
    Windows PowerShell 5.1. Run elevated (the launcher does it).
#>
param(
    [ValidateSet('Menu','Scan','SelfTest')]
    [string]$Action = 'Menu'
)

$ErrorActionPreference = 'Stop'
$Script:Version = '1.0.0'
$StateRoot      = Join-Path $env:ProgramData 'WindowsPCToolkit\Cleaner'
$LogRoot        = Join-Path $StateRoot 'Logs'
$RegBackupRoot  = Join-Path $StateRoot 'RegistryBackups'
$FileBackupRoot = Join-Path $StateRoot 'FileBackups'

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
    'OneDrive','Dropbox','Google Drive'
)

function Test-IsProtectedPath {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($segment in ($Path -split '[\\/]')) {
        if ($Script:ProtectedNames -contains $segment) { return $true }
    }
    return $false
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
            Risk='SAFE'; Profile='Balanced'; Kind='Files'; Paths=@("$L\CrashDumps\*.dmp","$W\Minidump\*.dmp","$W\MEMORY.DMP");
            Desc='Dumps from app/kernel crashes. Delete unless you are actively debugging a crash.' }
        [pscustomobject]@{ Id='INetCache';   Section='System'; Label='Legacy internet cache';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=@("$L\Microsoft\Windows\INetCache");
            Desc='Old WinINet/IE-era cache. Apps re-download what they need.' }
        [pscustomobject]@{ Id='DeliveryOptimization'; Section='System'; Label='Delivery Optimization cache';
            Risk='SAFE'; Profile='Balanced'; Kind='Special'; Paths=@();
            Desc='Update/Store delivery cache. Removed with the official Windows cmdlet.' }
        [pscustomobject]@{ Id='UpdateLogs';  Section='System'; Label='CBS/DISM servicing logs';
            Risk='SAFE'; Profile='Balanced'; Kind='Files'; Paths=@("$W\Logs\CBS\*.log","$W\Logs\DISM\*.log");
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
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=$gpuCaches;
            Desc='Compiled shader caches (NVIDIA/AMD/Intel/D3D). First launch of a game may stutter while they rebuild.' }
        [pscustomobject]@{ Id='IdeCaches';   Section='AI & Dev'; Label='VS Code / Cursor / Windsurf caches';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=$ideCaches;
            Desc='Editor caches and logs. Settings, extensions and history are not touched.' }
        [pscustomobject]@{ Id='AiAppCaches'; Section='AI & Dev'; Label='AI assistant model caches';
            Risk='SAFE'; Profile='Balanced'; Kind='Children'; Paths=$aiCaches;
            Desc='Edge/Chrome AI model stores and Copilot app caches. Re-downloaded on demand.' }
        [pscustomobject]@{ Id='BakFiles';    Section='Files'; Label='Patcher leftover backups (.bak/.old/.tmp/.orig)';
            Risk='SAFE'; Profile='Balanced'; Kind='Special'; Paths=@();
            Desc='Backups that sit next to their original file (mod patchers leave these). Files with no surviving original are kept.' }

        [pscustomobject]@{ Id='WUCache';     Section='System'; Label='Windows Update download cache';
            Risk='CAREFUL'; Profile='Strict'; Kind='Children'; Paths=@("$W\SoftwareDistribution\Download");
            Desc='Update downloads. Partial/stopped downloads re-download; in-progress ones are locked and skipped.' }
        [pscustomobject]@{ Id='Prefetch';    Section='System'; Label='Prefetch app-launch cache';
            Risk='CAREFUL'; Profile='Strict'; Kind='Children'; Paths=@("$W\Prefetch");
            Desc='App launch accelerator. Windows rebuilds it; first launches get slightly slower.' }
        [pscustomobject]@{ Id='PwaCaches';   Section='Browsers'; Label='PWA/service-worker caches';
            Risk='CAREFUL'; Profile='Strict'; Kind='Children'; Paths=$pwaCaches;
            Desc='Offline caches for installed web apps. Offline copies rebuild on next online visit.' }
        [pscustomobject]@{ Id='RecallData';  Section='AI & Dev'; Label='Windows Recall snapshots';
            Risk='STRICT'; Profile='Strict'; Kind='Children'; Paths=@("$L\CoreAIPlatform.00");
            Desc='Your searchable Recall screen history. Deleting this erases that history permanently.' }
        [pscustomobject]@{ Id='WindowsOld';  Section='System'; Label='Previous Windows installation (Windows.old)';
            Risk='STRICT'; Profile='Strict'; Kind='Special'; Paths=@();
            Desc='Left by a Windows upgrade. Removing frees many GB; rollback to the previous build becomes impossible.' }
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
            $out += @(Get-Item -Path $p -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer })
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
            $out += @(Get-ChildItem -Path $p -Force -File -ErrorAction SilentlyContinue)
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
                $items = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
                $files += $items.Count
                $bytes += [long](($items | Measure-Object -Property Length -Sum).Sum)
            }
        }
        'Files' {
            foreach ($f in Resolve-CategoryFiles -Category $Category) { $files++; $bytes += $f.Length }
        }
        'Report' {
            foreach ($dir in Resolve-CategoryDirs -Category $Category) {
                $items = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
                $files += $items.Count
                $bytes += [long](($items | Measure-Object -Property Length -Sum).Sum)
            }
        }
        'Special' {
            switch ($Category.Id) {
                'DeliveryOptimization' {
                    $p = Join-Path $env:SystemRoot 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization'
                    if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
                        $items = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)
                        $files += $items.Count
                        $bytes += [long](($items | Measure-Object -Property Length -Sum).Sum)
                    }
                }
                'BakFiles' {
                    $r = Get-BakCandidates
                    $files += @($r.Deletable).Count
                    foreach ($f in $r.Deletable) { $bytes += $f.Length }
                }
                'WindowsOld' {
                    $p = Join-Path $env:SystemDrive 'Windows.old'
                    if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
                        $items = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)
                        $files += $items.Count
                        $bytes += [long](($items | Measure-Object -Property Length -Sum).Sum)
                    }
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
        if ($Directory) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
        else            { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
        return $true
    } catch { return $false }
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
        if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container -ErrorAction SilentlyContinue)) { continue }
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
    $result = [pscustomobject]@{ Id = $Category.Id; Label = $Category.Label; Removed = 0; Skipped = 0; Bytes = [long]0; Note = '' }
    switch ($Category.Kind) {
        'Children' {
            foreach ($dir in Resolve-CategoryDirs -Category $Category) {
                foreach ($child in @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue)) {
                    if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { $result.Skipped++; continue }
                    $size = if ($child.PSIsContainer) {
                        [long](@(Get-ChildItem -LiteralPath $child.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum)
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
                            $result.Removed = $before.Files; $result.Bytes = $before.Bytes
                        } catch { $result.Note = $_.Exception.Message }
                    } else { $result.Note = 'cmdlet not available on this build' }
                }
                'BakFiles' {
                    $r = Get-BakCandidates
                    foreach ($f in $r.Deletable) {
                        if (Remove-ItemSafe -Path $f.FullName) { $result.Removed++; $result.Bytes += [long]$f.Length }
                        else { $result.Skipped++ }
                    }
                    $result.Note = "$(@($r.Orphans).Count) backup file(s) kept (no original found)"
                }
                'WindowsOld' {
                    $p = Join-Path $env:SystemDrive 'Windows.old'
                    if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
                        Write-Status Info 'Taking ownership of Windows.old (this can take several minutes)...'
                        & "$env:SystemRoot\System32\takeown.exe" /f $p /r /d y 2>&1 | Out-Null
                        & "$env:SystemRoot\System32\icacls.exe" $p /grant '*S-1-5-32-544:(OI)(CI)F' /t /c 2>&1 | Out-Null
                        $before = Measure-Category -Category $Category
                        if (Remove-ItemSafe -Path $p -Directory) { $result.Removed = $before.Files; $result.Bytes = $before.Bytes }
                        else { $result.Note = 'removal incomplete - some files are still protected' }
                    }
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
    }
    if (-not [IO.Path]::IsPathRooted($c)) { return $null }
    return $c
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
                if ($props.SystemComponent -eq 1) { continue }   # system-managed (KB entries etc.)
                $target = Get-CommandTargetPath ([string]$props.UninstallString)
                if ($target -and -not (Test-Path -LiteralPath $target)) {
                    [void]$issues.Add([pscustomobject]@{
                        Category = 'Orphaned uninstall entries'; Kind = 'Key'
                        Key = $k.PSPath; Name = $k.PSChildName
                        Display = [string]$props.DisplayName; Evidence = "missing: $target"
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
                if ($prop.Name -match '^PS') { continue }
                $target = Get-CommandTargetPath ([string]$prop.Value)
                if ($target -and -not (Test-Path -LiteralPath $target)) {
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
                if ($target -and [IO.Path]::IsPathRooted($target) -and -not (Test-Path -LiteralPath $target)) {
                    [void]$issues.Add([pscustomobject]@{
                        Category = 'Stale App Paths'; Kind = 'Key'
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
            if ($prop.Name -match '^PS') { continue }
            $pathPart = $prop.Name -replace '\.(FriendlyAppName|ApplicationCompany|NoRemove)$', ''
            if ($pathPart -notmatch '\\') { continue }
            $pathPart = [Environment]::ExpandEnvironmentVariables($pathPart)
            if ([IO.Path]::IsPathRooted($pathPart) -and -not (Test-Path -LiteralPath $pathPart)) {
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
                    if ($target -and [IO.Path]::IsPathRooted($target) -and -not (Test-Path -LiteralPath $target)) {
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
    Assert-Admin; Initialize-State
    Write-Host ''
    Write-Status Step 'Scanning registry for provably orphaned entries...'
    $issues = Get-RegistryIssues
    $total = @($issues).Count
    if ($total -eq 0) {
        Write-Status OK 'No orphaned registry entries found.'
        return
    }
    $i = 0
    foreach ($group in ($issues | Group-Object Category)) {
        Write-Host ''
        Write-Host ("  {0} ({1})" -f $group.Name, $group.Count) -ForegroundColor Cyan
        foreach ($item in $group.Group) {
            $i++
            Write-Host ("   [{0}] {1}  ({2})" -f $i, $item.Display, $item.Evidence)
        }
    }
    Write-Host ''
    Write-Status Info 'Only provably orphaned entries are listed. Every removal is exported to a .reg backup first.'
    $pick = Read-Host '  Remove which? [A]ll, comma list like 1,3-5, or 0 to cancel'
    if ($pick -eq '0' -or [string]::IsNullOrWhiteSpace($pick)) { Write-Status Skip 'No changes made.'; return }

    $selected = @()
    if ($pick -match '^[Aa]$') { $selected = @($issues) }
    else {
        foreach ($part in ($pick -split ',')) {
            if ($part -match '^\s*(\d+)\s*-\s*(\d+)\s*$') {
                foreach ($n in ([int]$Matches[1])..([int]$Matches[2])) {
                    if ($n -ge 1 -and $n -le @($issues).Count) { $selected += $issues[$n - 1] }
                }
            } elseif ($part -match '^\s*(\d+)\s*$') {
                $idx = [int]$Matches[1]
                if ($idx -ge 1 -and $idx -le @($issues).Count) { $selected += $issues[$idx - 1] }
            }
        }
        $selected = @($selected | Where-Object { $_ })
    }
    if (@($selected).Count -eq 0) { Write-Status Skip 'Nothing valid selected.'; return }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $runDir = Join-Path $RegBackupRoot $stamp
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    $manifest = New-Object System.Collections.ArrayList
    $n = 0; $removed = 0; $failed = 0
    foreach ($item in $selected) {
        $n++
        switch ($item.Kind) {
            'Key' {
                $backup = Join-Path $runDir ("{0:d3}_key.reg" -f $n)
                $regPath = ($item.Key -replace '^.*Registry::', '') -replace '^HKLM:', 'HKEY_LOCAL_MACHINE' -replace '^HKCU:', 'HKEY_CURRENT_USER'
                & "$env:SystemRoot\System32\reg.exe" export $regPath $backup /y 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { Write-Status Warn "Backup failed for $($item.Name) - skipped."; $failed++; continue }
                try {
                    Remove-Item -LiteralPath $item.Key -Recurse -Force -ErrorAction Stop
                    [void]$manifest.Add(@{ Type = 'Key'; Path = $item.Key; Backup = $backup })
                    Write-Status OK "Removed: $($item.Name)"
                    $removed++
                } catch { Write-Status Fail "Could not remove $($item.Name): $($_.Exception.Message)"; $failed++ }
            }
            'Value' {
                $backup = Join-Path $runDir ("{0:d3}_value.reg" -f $n)
                $regPath = ($item.Key -replace '^.*Registry::', '') -replace '^HKLM:', 'HKEY_LOCAL_MACHINE' -replace '^HKCU:', 'HKEY_CURRENT_USER'
                & "$env:SystemRoot\System32\reg.exe" export $regPath $backup /y 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { Write-Status Warn "Backup failed for $($item.Name) - skipped."; $failed++; continue }
                try {
                    Remove-ItemProperty -LiteralPath $item.Key -Name $item.Name -ErrorAction Stop
                    [void]$manifest.Add(@{ Type = 'Value'; Key = $item.Key; Name = $item.Name; Backup = $backup })
                    Write-Status OK "Removed: $($item.Name)"
                    $removed++
                } catch { Write-Status Fail "Could not remove $($item.Name): $($_.Exception.Message)"; $failed++ }
            }
            'File' {
                try {
                    $fileBackup = Join-Path (Join-Path $FileBackupRoot $stamp) $item.Name
                    New-Item -ItemType Directory -Path (Split-Path $fileBackup -Parent) -Force | Out-Null
                    Copy-Item -LiteralPath $item.Key -Destination $fileBackup -Force -ErrorAction Stop
                    Remove-Item -LiteralPath $item.Key -Force -ErrorAction Stop
                    [void]$manifest.Add(@{ Type = 'File'; Path = $item.Key; Backup = $fileBackup })
                    Write-Status OK "Removed: $($item.Name)"
                    $removed++
                } catch { Write-Status Fail "Could not remove $($item.Name): $($_.Exception.Message)"; $failed++ }
            }
        }
    }
    $manifestPath = Join-Path $runDir 'manifest.json'
    ([pscustomobject]@{ Created = (Get-Date).ToString('o'); Removed = $removed; Failed = $failed; Items = @($manifest) } |
        ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Host ''
    Write-Status OK "Registry care complete: $removed removed, $failed failed."
    Write-Status Info "Backups: $runDir  (restore with menu option 7)"
}

function Restore-LatestRegistryBackup {
    Assert-Admin
    $latest = Get-ChildItem -LiteralPath $RegBackupRoot -Directory -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { Write-Status Warn 'No registry backups exist yet.'; return }
    $manifestPath = Join-Path $latest.FullName 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -ErrorAction SilentlyContinue)) { Write-Status Warn 'Latest backup has no manifest.'; return }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Write-Status Info ("Restoring backup from {0} ({1} item(s))..." -f $latest.Name, @($manifest.Items).Count)
    $restored = 0
    foreach ($item in @($manifest.Items)) {
        if ($item.Type -eq 'File') {
            try {
                $dest = Split-Path $item.Path -Parent
                if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                Copy-Item -LiteralPath $item.Backup -Destination $item.Path -Force -ErrorAction Stop
                Write-Status OK "Restored file: $(Split-Path $item.Path -Leaf)"
                $restored++
            } catch { Write-Status Fail "Could not restore $($item.Path): $($_.Exception.Message)" }
        } else {
            if (Test-Path -LiteralPath $item.Backup -ErrorAction SilentlyContinue) {
                & "$env:SystemRoot\System32\reg.exe" import $item.Backup 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Status OK "Imported: $(Split-Path $item.Backup -Leaf)"; $restored++ }
                else { Write-Status Fail "Import failed: $($item.Backup)" }
            }
        }
    }
    Write-Status OK "Restored $restored item(s). A sign-out may be needed for startup entries."
}

# ============================================================================
#  SCAN REPORT + PROFILES
# ============================================================================

function Show-ScanLine {
    param($Category, $Info, [string]$Prefix = '')
    $tag = switch ($Category.Risk) {
        'SAFE'    { '[SAFE]   ' } 'CAREFUL' { '[CAREFUL]' }
        'STRICT'  { '[STRICT] ' } 'REPORT'  { '[KEEP]   ' }
        default   { '[----]   ' }
    }
    $color = switch ($Category.Risk) { 'SAFE' { 'Green' } 'CAREFUL' { 'Yellow' } 'STRICT' { 'Red' } default { 'DarkCyan' } }
    Write-Host ("  $Prefix{0} {1,12}  {2,7} files  " -f $tag, (Format-Size $Info.Bytes), $Info.Files) -ForegroundColor $color -NoNewline
    Write-Host $Category.Label
    Write-Host ("           {0}" -f $Category.Desc) -ForegroundColor DarkGray
}

function Show-ScanReport {
    $cats = Get-CleanCategories
    $rep  = Get-ReportCategories
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
    $path = Join-Path $LogRoot ("clean_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $obj = [pscustomobject]@{
        Tool = 'PC Cleaner'; Version = $Script:Version; Profile = $Name
        Created = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME
        FreeBeforeBytes = $FreeBefore; FreeAfterBytes = $FreeAfter
        TotalRemovedBytes = [long](($Results | Measure-Object -Property Bytes -Sum).Sum)
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
        Write-Status OK ("{0}: removed {1} item(s), freed {2}{3}" -f $c.Label, $r.Removed, (Format-Size $r.Bytes),
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
    Write-Status OK ("{0} clean complete: {1} item(s) removed, {2} skipped, {3} freed." -f $Name, $totalRemoved, $totalSkipped, (Format-Size $totalBytes))
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
        if ($part -match '^\s*(\d+)\s*-\s*(\d+)\s*$') { foreach ($n in ([int]$Matches[1])..([int]$Matches[2])) { if ($n -ge 1 -and $n -le $cats.Count) { $selected += $cats[$n - 1] } } }
        elseif ($part -match '^\s*(\d+)\s*$') { $idx = [int]$Matches[1]; if ($idx -ge 1 -and $idx -le $cats.Count) { $selected += $cats[$idx - 1] } }
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
        Write-Status OK ("{0}: removed {1} item(s), freed {2}{3}" -f $c.Label, $r.Removed, (Format-Size $r.Bytes),
            $(if ($r.Skipped -gt 0) { " ($($r.Skipped) locked/in-use skipped)" } else { '' }))
    }
    $log = Save-RunLog -Name 'Custom' -Results $results -FreeBefore $freeBefore -FreeAfter (Get-FreeSpaceBytes)
    Write-Status OK ("Custom clean complete. Log: {0}" -f $log)
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
            } catch { Write-Status Fail $_.Exception.Message }
        }
    }
}
