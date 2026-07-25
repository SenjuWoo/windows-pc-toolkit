<#
.SYNOPSIS
    PC Corruption Fixer v7.1 - Advanced system repair and diagnostics toolkit.
.DESCRIPTION
    Repairs corrupted system files, fixes Windows Update safely, clears caches,
    resets networking, deep-cleans components, checks disk health, manages
    services, scans event logs, diagnoses network/drivers/disk space, and
    exports a full HTML health report. All operations are logged.
.NOTES
    Requires Administrator. Run via Fix_Corruption.bat or right-click -> Run with PowerShell.
    Log file saved to: $env:USERPROFILE\Desktop\PC_Fixer_Log_*.txt

    v7.1 CHANGES:
    - REBUILT: AI Feature Privacy [23] is now policy-only and fully reversible.
      It no longer disables services, removes AppX packages, or breaks Windows
      Search. Exact registry state is saved before every change.

    v7.0 CHANGES:
    - FIXED: Disk scan now uses Repair-Volume -Scan first. chkdsk /scan is a
      fallback, so PowerShell pipeline access-denied failures no longer create
      a false CHKDSK failure. Timing includes every fallback path.
    - SAFER FULL REPAIR: no longer resets Winsock/TCP/IP during routine system
      repair. It performs a non-destructive network/DNS health refresh instead.
    - DNS-SAFE RESET: explicit Network Reset snapshots and restores adapter DNS
      addresses and DoH templates so encrypted DNS is not silently erased.
    - SAFE CACHE DEFAULT: Recycle Bin deletion is separately opt-in.
    - DASHBOARD: a stopped Manual/trigger-start Windows Update service is shown
      as ready, not falsely reported as broken.

    v6.3 CHANGES:
    - SLEEP-FREE: long repairs (SFC/DISM/Full Repair/WU) block modern standby so
      the PC cannot sleep mid-scan; stay-awake is always released on exit.
    - Network Diagnostics now reports DNS-over-HTTPS (DoH) template status.
    - TcpClient disposed cleanly; launcher version aligned to 6.3.

    v6.2 CHANGES (legacy behavior removed in v7.1):
    - The old AI-bloat routine used destructive service/AppX/search edits. v7.1
      replaces it with a reversible policy manager.

    v6.1 CHANGES:
    - NEW: Fix Performance Counters [21] - lodctr /R rebuild (64+32-bit) plus
      WMI resync; fixes Perflib event-log errors and broken perf graphs.
    - NEW: Orphaned Service Cleanup [22] - finds services whose program no
      longer exists on disk (leftovers from uninstalled apps) and optionally
      removes them, with per-service confirmation.
    - FIXED: Service Health Check no longer flags demand-start (Manual)
      services like BITS as problems - stopped is their normal idle state.

    v6.0 CHANGES (Security + Feature release):
    - SECURITY: All system tools (sfc, DISM, chkdsk, netsh, regsvr32, etc.) and
      re-registered DLLs are now invoked by ABSOLUTE System32 path. Previously
      they were called by bare name through cmd.exe, so a malicious sfc.exe or
      atl.dll planted next to the script (e.g. on the shared USB/cloud folder)
      could run with Administrator rights (binary/DLL search-order hijack). The
      cmd.exe middleman is gone entirely - executables are launched directly.
    - SECURITY: Removed cmd.exe /c argument concatenation (command-injection
      surface); native processes now receive an explicit argument array.
    - NEW: All 8 previously-documented-but-missing features are now implemented:
      Windows Update Health Check, Network Diagnostics, Rebuild Icon/Thumbnail
      Cache, Repair Time Sync, Problem Device Scan, Disk Space Analyzer, Startup
      Programs Viewer, and Export HTML Health Report.
    - FIXED: CBS.log is now tailed (-Tail) instead of fully loaded into RAM.
    - FIXED: WSReset no longer pops the Store window open during Clear Caches.
    - FIXED: Duplicate firewall service removed from the critical-services list.
    - FIXED: Quick Health Scan service check no longer relies on a non-existent
      variable; it now reports service health accurately.
    - IMPROVED: Full Repair asks before the disruptive network/firewall reset.
    - IMPROVED: Old log files are auto-pruned (keeps the 15 most recent).
    - IMPROVED: Reorganized, categorized 20-option menu.

    v5.0 CHANGES:
    - IMPROVED: WU repair also stops Delivery Optimization and warns on pending
      reboot before resetting
    - IMPROVED: True-color ANSI gradient banner, dashboard usage bars

    v4.0 CHANGES:
    - FIXED: No longer breaks Windows Updates (removed dangerous WU cache deletion)
    - NEW: Dedicated Windows Update SAFE repair feature
    - NEW: System Restore Point creation, Critical Services check, Store reset,
      Event Log scanner, Quick Health Scan, pending reboot detection
#>

#Requires -RunAsAdministrator

$ProgressPreference = 'SilentlyContinue'

# ============================================================================
#  CONFIGURATION
# ============================================================================

$Script:Version    = '7.1.1'
$Script:LogDir     = "$env:USERPROFILE\Desktop"
$Script:LogName    = "PC_Fixer_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$Script:LogPath    = Join-Path $Script:LogDir $Script:LogName
$Script:LogKeep    = 15          # number of past log files to retain
$Script:StartTime  = Get-Date
$Script:Results    = [ordered]@{}
$Script:HasFailure = $false
$Script:StepNum    = 0
$Script:TotalSteps = 0
$Script:StayAwakeArmed = $false

# Absolute path to the trusted System32 directory. Every native Windows tool
# and every DLL this script touches is resolved under here so that a binary
# planted in the (possibly untrusted) script folder can never be executed.
$Script:Sys32      = Join-Path ([System.Environment]::SystemDirectory) ''
if ([string]::IsNullOrWhiteSpace($Script:Sys32) -or -not (Test-Path -LiteralPath $Script:Sys32)) {
    $Script:Sys32 = Join-Path $env:SystemRoot 'System32'
}

# Box-drawing characters (safe for Windows 10/11 conhost + Windows Terminal)
$B = @{
    TL = [string][char]0x2554   # ╔
    TR = [string][char]0x2557   # ╗
    BL = [string][char]0x255A   # ╚
    BR = [string][char]0x255D   # ╝
    H  = [string][char]0x2550   # ═
    V  = [string][char]0x2551   # ║
    LT = [string][char]0x2560   # ╠
    RT = [string][char]0x2563   # ╣
    MH = [string][char]0x2500   # ─
    Fill = [string][char]0x2588 # █
    Empty = [string][char]0x2591 # ░
}

# ---------------------------------------------------------------------------
#  ANSI / TRUE-COLOR SUPPORT
#  Windows Terminal has VT enabled by default; classic conhost needs
#  SetConsoleMode with ENABLE_VIRTUAL_TERMINAL_PROCESSING (0x4).
#  If anything fails we fall back to plain 16-color output.
# ---------------------------------------------------------------------------

$Script:Esc  = [char]27
$Script:Ansi = $false
try {
    $vtSig = @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
    $vt = Add-Type -MemberDefinition $vtSig -Name 'ConsoleVT' -Namespace 'PCFixer' -PassThru -ErrorAction Stop
    $stdout = $vt::GetStdHandle(-11)
    $mode = [uint32]0
    if ($vt::GetConsoleMode($stdout, [ref]$mode)) {
        if (($mode -band 4) -eq 4 -or $vt::SetConsoleMode($stdout, $mode -bor 4)) {
            $Script:Ansi = $true
        }
    }
} catch { $Script:Ansi = $false }

function Write-Gradient {
    # Prints one line of text with a smooth left-to-right RGB gradient.
    param(
        [string]$Text,
        [int[]]$From = @(0, 210, 255),    # cyan
        [int[]]$To   = @(170, 90, 255),   # violet
        [string]$Fallback = 'Cyan'
    )
    if (-not $Script:Ansi -or [string]::IsNullOrEmpty($Text)) {
        Write-Host $Text -ForegroundColor $Fallback
        return
    }
    $len = $Text.Length
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $len; $i++) {
        $t = if ($len -gt 1) { $i / ($len - 1) } else { 0.0 }
        $r = [int]($From[0] + ($To[0] - $From[0]) * $t)
        $g = [int]($From[1] + ($To[1] - $From[1]) * $t)
        $bl = [int]($From[2] + ($To[2] - $From[2]) * $t)
        [void]$sb.Append("$Script:Esc[38;2;$r;$g;${bl}m").Append($Text[$i])
    }
    [void]$sb.Append("$Script:Esc[0m")
    Write-Host $sb.ToString()
}

function Get-UsageBar {
    # Returns a mini bar like [######......] for dashboard rows.
    param([double]$Percent, [int]$Width = 20)
    $p = [math]::Max(0, [math]::Min(100, $Percent))
    $filled = [int][math]::Round($p / 100 * $Width)
    return ($B.Fill * $filled) + ($B.Empty * ($Width - $filled))
}

# ============================================================================
#  LOGGING
# ============================================================================

try {
    Start-Transcript -Path $Script:LogPath -Append -ErrorAction SilentlyContinue | Out-Null
} catch { }

# Prune old logs so the Desktop doesn't fill up (keeps the newest $Script:LogKeep).
try {
    Get-ChildItem -Path (Join-Path $Script:LogDir 'PC_Fixer_Log_*.txt') -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Script:LogKeep |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch { }

# ============================================================================
#  UTILITY FUNCTIONS
# ============================================================================

# ---------------------------------------------------------------------------
#  STAY-AWAKE (sleep-free long repairs)
#  SFC/DISM can run 5-30+ minutes; modern standby would otherwise suspend
#  mid-repair and leave the system half-fixed. Always pair with AllowSleep.
# ---------------------------------------------------------------------------
try {
    $stayAwakeSrc = @'
using System;
using System.Runtime.InteropServices;
public static class FixerStayAwake {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
    public const uint ES_CONTINUOUS = 0x80000000;
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
    public const uint ES_AWAYMODE_REQUIRED = 0x00000040;
    public static void PreventSleep() {
        SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
    }
    public static void AllowSleep() {
        SetThreadExecutionState(ES_CONTINUOUS);
    }
}
'@
    if (-not ('FixerStayAwake' -as [type])) {
        Add-Type -TypeDefinition $stayAwakeSrc -ErrorAction Stop
    }
} catch { }

function Enable-StayAwake {
    try {
        if ('FixerStayAwake' -as [type]) {
            [FixerStayAwake]::PreventSleep()
            $Script:StayAwakeArmed = $true
        }
    } catch { }
}

function Disable-StayAwake {
    try {
        if (('FixerStayAwake' -as [type]) -and $Script:StayAwakeArmed) {
            [FixerStayAwake]::AllowSleep()
            $Script:StayAwakeArmed = $false
        }
    } catch { }
}

function Resolve-SystemTool {
    # SECURITY: resolves a tool name to its absolute path under a trusted
    # Windows directory (System32 by default; a caller may name another folder
    # such as SysWOW64, but anything outside %SystemRoot% is refused). Never
    # falls back to PATH or the current directory, so a malicious sfc.exe /
    # DISM.exe planted next to this script can never be executed.
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$BaseDir
    )
    $leaf = Split-Path -Leaf $Name
    $root = if ([string]::IsNullOrWhiteSpace($BaseDir)) { $Script:Sys32 } else { $BaseDir }
    $winRoot = $env:SystemRoot.TrimEnd('\') + '\'
    if (-not ($root.TrimEnd('\') + '\').StartsWith($winRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    $full = Join-Path $root $leaf
    if (Test-Path -LiteralPath $full) { return $full }
    return $null
}

function Invoke-Native {
    # Runs a System32 tool directly (no cmd.exe middleman), streams its output
    # to the console/log, and returns @{ ExitCode; Output }.
    # - sfc.exe emits UTF-16 text: the console encoding is switched for the
    #   duration of that call so output is decoded correctly (fixes the
    #   "V e r i f i c a t i o n" mangling seen in transcripts).
    # - Consecutive duplicate lines (progress spam) are collapsed.
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$Quiet,
        [string]$BaseDir
    )
    $exe = Resolve-SystemTool $FilePath -BaseDir $BaseDir
    if (-not $exe) {
        $msg = "Tool not found in System32: $FilePath"
        if (-not $Quiet) { Write-Warning $msg }
        return [PSCustomObject]@{ ExitCode = 9009; Output = $msg }
    }

    $outputBuilder = New-Object System.Text.StringBuilder
    $exitCode = 0
    $leaf = [System.IO.Path]::GetFileName($exe).ToLowerInvariant()
    $prevEncoding = $null
    try {
        if ($leaf -eq 'sfc.exe') {
            try {
                $prevEncoding = [Console]::OutputEncoding
                [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
            } catch { $prevEncoding = $null }
        }
        $prevLine = $null
        & $exe @ArgumentList 2>&1 | ForEach-Object {
            $line = if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.Exception.Message
            } else { $_.ToString() }
            $line = $line.Trim([char]0).TrimEnd()
            if ($line.Trim().Length -gt 0 -and $line -ne $prevLine) {
                [void]$outputBuilder.AppendLine($line)
                if (-not $Quiet) { Write-Host $line }
                $prevLine = $line
            }
        }
        $exitCode = $LASTEXITCODE
    } catch {
        $errMsg = "ERROR running $leaf : $_"
        [void]$outputBuilder.AppendLine($errMsg)
        if (-not $Quiet) { Write-Warning $errMsg }
        $exitCode = 1
    } finally {
        if ($null -ne $prevEncoding) {
            try { [Console]::OutputEncoding = $prevEncoding } catch { }
        }
    }
    [PSCustomObject]@{ ExitCode = $exitCode; Output = $outputBuilder.ToString() }
}

function Invoke-Native-Quiet {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$BaseDir
    )
    Invoke-Native -FilePath $FilePath -ArgumentList $ArgumentList -Quiet -BaseDir $BaseDir
}


function Invoke-NativeProcessSafe {
    # ProcessStartInfo fallback for native tools that PowerShell's invocation
    # pipeline refuses to start. Intended for short, simple argument lists.
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$Quiet,
        [string]$BaseDir
    )
    $exe = Resolve-SystemTool $FilePath -BaseDir $BaseDir
    if (-not $exe) { return [PSCustomObject]@{ ExitCode = 9009; Output = "Tool not found: $FilePath" } }
    $quoted = foreach ($arg in $ArgumentList) {
        if ($arg -match '[\s"]') { '"' + ($arg -replace '"','\"') + '"' } else { $arg }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ($quoted -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        if (-not $process.Start()) { throw 'Process did not start.' }
        # Read both streams concurrently to avoid a full stderr/stdout pipe
        # blocking the child process on unusually verbose native tools.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $parts = @()
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { $parts += $stdout }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { $parts += $stderr }
        $output = ($parts -join [Environment]::NewLine).Trim()
        if (-not $Quiet -and $output) { Write-Host $output }
        return [PSCustomObject]@{ ExitCode = $process.ExitCode; Output = $output }
    } catch {
        $message = "ERROR running $([IO.Path]::GetFileName($exe)): $($_.Exception.Message)"
        if (-not $Quiet) { Write-Warning $message }
        return [PSCustomObject]@{ ExitCode = 1; Output = $message }
    } finally { $process.Dispose() }
}

function Stop-ServiceSafely {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Stop-Service -Name $Name -Force -ErrorAction Stop
        }
        return $true
    } catch { return $false }
}

function Start-ServiceSafely {
    param([string]$Name)
    try {
        Start-Service -Name $Name -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-Elapsed {
    param([System.Diagnostics.Stopwatch]$Timer)
    $ts = $Timer.Elapsed
    if ($ts.TotalHours -ge 1) {
        return "$([int]$ts.TotalHours)h $($ts.Minutes)m $($ts.Seconds)s"
    }
    if ($ts.TotalMinutes -ge 1) {
        return "$($ts.Minutes)m $($ts.Seconds)s"
    }
    return "$($ts.TotalSeconds.ToString('F1'))s"
}

function Test-PendingReboot {
    $pending = $false
    $reasons = @()

    $cbsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    if (Test-Path $cbsKey) { $pending = $true; $reasons += 'Component Based Servicing' }

    $wuKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    if (Test-Path $wuKey) { $pending = $true; $reasons += 'Windows Update' }

    $renameKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $renames = (Get-ItemProperty $renameKey -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($renames) { $pending = $true; $reasons += 'Pending file renames' }

    [PSCustomObject]@{ Pending = $pending; Reasons = $reasons }
}

# ============================================================================
#  DISPLAY FUNCTIONS
# ============================================================================

function Write-Box {
    param([string]$Text, [string]$Color = 'Cyan', [int]$Width = 64)
    $inner = $Width - 2
    Write-Host "  $($B.TL)$($B.H * $inner)$($B.TR)" -ForegroundColor $Color
    Write-Host "  $($B.V)" -ForegroundColor $Color -NoNewline
    Write-Host (" $Text".PadRight($inner)) -NoNewline
    Write-Host "$($B.V)" -ForegroundColor $Color
    Write-Host "  $($B.BL)$($B.H * $inner)$($B.BR)" -ForegroundColor $Color
}

function Write-DoubleBox {
    param([string]$Line1, [string]$Line2, [string]$Color = 'Cyan', [int]$Width = 64)
    $inner = $Width - 2
    Write-Host "  $($B.TL)$($B.H * $inner)$($B.TR)" -ForegroundColor $Color
    Write-Host "  $($B.V)" -ForegroundColor $Color -NoNewline
    Write-Host (" $Line1".PadRight($inner)) -NoNewline
    Write-Host "$($B.V)" -ForegroundColor $Color
    Write-Host "  $($B.V)" -ForegroundColor $Color -NoNewline
    Write-Host (" $Line2".PadRight($inner)) -NoNewline
    Write-Host "$($B.V)" -ForegroundColor $Color
    Write-Host "  $($B.BL)$($B.H * $inner)$($B.BR)" -ForegroundColor $Color
}

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host "  $($B.MH * 62)" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor Yellow
    Write-Host "  $($B.MH * 62)" -ForegroundColor DarkGray
    Write-Host ''
}

function Write-Status {
    param(
        [ValidateSet('OK','Fail','Warn','Skip','Info','Step')][string]$Type,
        [string]$Text
    )
    $map = @{
        OK   = @{ Tag = '  [OK] ';  Color = 'Green'  }
        Fail = @{ Tag = '  [XX] ';  Color = 'Red'    }
        Warn = @{ Tag = '  [!!] ';  Color = 'Yellow' }
        Skip = @{ Tag = '  [>>] ';  Color = 'DarkCyan' }
        Info = @{ Tag = '     ';    Color = 'Gray'   }
        Step = @{ Tag = '  [=>] ';  Color = 'Cyan'   }
    }
    $m = $map[$Type]
    Write-Host "$($m.Tag)" -ForegroundColor $m.Color -NoNewline
    Write-Host $Text -ForegroundColor $(if ($Type -eq 'Info') { 'Gray' } else { 'White' })
}

function Write-StepHeader {
    param([string]$Title, [int]$Number = 0, [int]$Total = 0)
    $prefix = ''
    if ($Total -gt 0) {
        $Script:StepNum = $Number
        $Script:TotalSteps = $Total
        $prefix = "[Step $Number/$Total] "
    }
    Write-Host ''
    Write-Host ("  " + $B.H * 62) -ForegroundColor DarkCyan
    Write-Host "  $prefix$Title" -ForegroundColor Yellow
    Write-Host ("  " + $B.H * 62) -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-ProgressBar {
    param([int]$Current, [int]$Total, [int]$Width = 30)
    if ($Total -eq 0) { return }
    $pct = [math]::Min([math]::Round(($Current / $Total) * 100), 100)
    $filled = [math]::Round($Current / $Total * $Width)
    $empty = $Width - $filled
    $bar = ($B.Fill * $filled) + ($B.Empty * $empty)
    Write-Host ''
    Write-Host "  Overall Progress: [$bar] $pct%  ($Current/$Total)" -ForegroundColor Cyan
}

function Write-Result {
    param([string]$Name, [string]$Value, [switch]$Failed, [switch]$Warning)
    $color = if ($Failed) { 'Red' } elseif ($Warning) { 'Yellow' } else { 'Green' }
    Write-Host ("  {0,-18} {1}" -f "[$Name]", $Value) -ForegroundColor $color
}

# ============================================================================
#  BANNER & DASHBOARD
# ============================================================================

function Show-Banner {
    Clear-Host
    $w = 64
    $inner = $w - 2
    Write-Host ''
    Write-Host "  $($B.TL)$($B.H * $inner)$($B.TR)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host ''.PadRight($inner) -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host '  ____   _____   ____   ___   _   _ __     __ ____  _____'.PadRight($inner) -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host '  |  _ \ / ____| / ___| / _ \ | | | |\ \   / /|  _ \|  ___|'.PadRight($inner) -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host '  | |_) | |     | |    | | | || | | | \ \ / / | | | | |_   '.PadRight($inner) -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host '  |  __/| |___  | |___ | |_| || |_| |  \ V /  | |_| |  _|  '.PadRight($inner) -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host '  |_|    \_____| \____| \___/  \___/    \_/   |____/|_|    '.PadRight($inner) -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host ''.PadRight($inner) -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host "  PC CORRUPTION FIXER  v$Script:Version".PadRight($inner) -ForegroundColor Yellow -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host '  Repair - Clean - Fix - Optimize - Protect'.PadRight($inner) -ForegroundColor Gray -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host ''.PadRight($inner) -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.BL)$($B.H * $inner)$($B.BR)" -ForegroundColor Cyan
    Write-Host ''
    Write-Host "  Log: $Script:LogPath" -ForegroundColor DarkGray
    Write-Host ''
}

function Show-Dashboard {
    Write-Host '  SYSTEM DASHBOARD' -ForegroundColor Cyan
    Write-Host "  $($B.MH * 58)" -ForegroundColor DarkGray

    # CPU
    try {
        $cpu = (Get-CimInstance Win32_Processor -EA Stop | Select-Object -First 1).Name -replace '\s+', ' '
        if ($cpu.Length -gt 50) { $cpu = $cpu.Substring(0, 47) + '...' }
        Write-Host '  CPU      : ' -ForegroundColor Gray -NoNewline
        Write-Host $cpu -ForegroundColor White
    } catch { Write-Host '  CPU      : (unavailable)' -ForegroundColor DarkGray }

    # OS
    try {
        $os = Get-CimInstance Win32_OperatingSystem -EA Stop
        Write-Host '  OS       : ' -ForegroundColor Gray -NoNewline
        Write-Host "$($os.Caption)  Build $($os.BuildNumber)" -ForegroundColor White
        $uptime = (Get-Date) - $os.LastBootUpTime
        Write-Host '  Uptime   : ' -ForegroundColor Gray -NoNewline
        Write-Host "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m" -ForegroundColor White
    } catch { Write-Host '  OS       : (unavailable)' -ForegroundColor DarkGray }

    # Disk
    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -EA Stop
        $freeGB  = [math]::Round($disk.FreeSpace / 1GB, 1)
        $totalGB = [math]::Round($disk.Size / 1GB, 1)
        $pctFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
        $diskColor = if ($pctFree -lt 10) { 'Red' } elseif ($pctFree -lt 20) { 'Yellow' } else { 'White' }
        Write-Host '  C: Drive : ' -ForegroundColor Gray -NoNewline
        Write-Host "$freeGB GB free / $totalGB GB  " -ForegroundColor $diskColor -NoNewline
        Write-Host (Get-UsageBar (100 - $pctFree) 14) -ForegroundColor DarkCyan -NoNewline
        Write-Host " $pctFree% free" -ForegroundColor $diskColor
    } catch { Write-Host '  C: Drive : (unavailable)' -ForegroundColor DarkGray }

    # RAM
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -EA Stop
        $os2 = Get-CimInstance Win32_OperatingSystem -EA Stop
        $totalRam = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        $freeRam  = [math]::Round($os2.FreePhysicalMemory / 1MB, 1)
        $usedRam  = [math]::Round($totalRam - $freeRam, 1)
        $ramPct   = [math]::Round(($usedRam / $totalRam) * 100, 0)
        $ramColor = if ($ramPct -gt 90) { 'Red' } elseif ($ramPct -gt 75) { 'Yellow' } else { 'White' }
        Write-Host '  RAM      : ' -ForegroundColor Gray -NoNewline
        Write-Host "$usedRam GB used / $totalRam GB  " -ForegroundColor $ramColor -NoNewline
        Write-Host (Get-UsageBar $ramPct 14) -ForegroundColor DarkCyan -NoNewline
        Write-Host " $ramPct%" -ForegroundColor $ramColor
    } catch { Write-Host '  RAM      : (unavailable)' -ForegroundColor DarkGray }

    # Windows Defender
    try {
        $defSvc = Get-Service -Name WinDefend -EA SilentlyContinue
        $mpStatus = Get-MpComputerStatus -EA SilentlyContinue
        if ($defSvc -and $defSvc.Status -eq 'Running' -and $mpStatus) {
            $sigAge = (Get-Date) - $mpStatus.AntivirusSignatureLastUpdated
            $sigColor = if ($sigAge.Days -gt 3) { 'Yellow' } else { 'White' }
            Write-Host '  Defender : ' -ForegroundColor Gray -NoNewline
            Write-Host "Active  (definitions: $($sigAge.Days)d ago)" -ForegroundColor $sigColor
        } else {
            Write-Host '  Defender : ' -ForegroundColor Gray -NoNewline
            Write-Host 'Not running' -ForegroundColor Red
        }
    } catch {
        Write-Host '  Defender : ' -ForegroundColor Gray -NoNewline
        Write-Host '(unavailable)' -ForegroundColor DarkGray
    }

    # Windows Update uses Manual/trigger start on modern Windows and normally
    # stops while idle. Stopped is healthy unless the service is disabled.
    try {
        $wuSvc = Get-Service -Name wuauserv -EA SilentlyContinue
        $wuCim = Get-CimInstance Win32_Service -Filter "Name='wuauserv'" -EA SilentlyContinue
        $wuDetectKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect'
        $wuDetect = (Get-ItemProperty $wuDetectKey -Name 'LastSuccessTime' -EA SilentlyContinue).LastSuccessTime
        Write-Host '  Win Upd  : ' -ForegroundColor Gray -NoNewline
        if (-not $wuSvc -or -not $wuCim) {
            Write-Host 'Service unavailable' -ForegroundColor Yellow
        } elseif ($wuCim.StartMode -eq 'Disabled') {
            Write-Host 'DISABLED' -ForegroundColor Red
        } elseif ($wuSvc.Status -eq 'Running') {
            $wuText = "Running ($($wuCim.StartMode))"
            if ($wuDetect) { $wuText += "  (last scan: $wuDetect)" }
            Write-Host $wuText -ForegroundColor White
        } else {
            $wuText = "Ready ($($wuCim.StartMode)/trigger start; idle now)"
            if ($wuDetect) { $wuText += "  (last scan: $wuDetect)" }
            Write-Host $wuText -ForegroundColor Green
        }
    } catch {
        Write-Host '  Win Upd  : ' -ForegroundColor Gray -NoNewline
        Write-Host '(unavailable)' -ForegroundColor DarkGray
    }

    # Network adapter
    try {
        $netAdapters = Get-NetAdapter -EA Stop | Where-Object { $_.Status -eq 'Up' }
        if ($netAdapters) {
            $names = ($netAdapters | Select-Object -First 2 | ForEach-Object { $_.Name }) -join ', '
            Write-Host '  Network  : ' -ForegroundColor Gray -NoNewline
            Write-Host "Connected ($names)" -ForegroundColor Green
        } else {
            Write-Host '  Network  : ' -ForegroundColor Gray -NoNewline
            Write-Host 'No active adapters' -ForegroundColor Red
        }
    } catch {
        Write-Host '  Network  : ' -ForegroundColor Gray -NoNewline
        Write-Host '(unavailable)' -ForegroundColor DarkGray
    }

    # Pending reboot
    $pbr = Test-PendingReboot
    Write-Host '  Reboot   : ' -ForegroundColor Gray -NoNewline
    if ($pbr.Pending) {
        Write-Host "PENDING ($($pbr.Reasons -join ', '))" -ForegroundColor Yellow
    } else {
        Write-Host 'Not required' -ForegroundColor Green
    }

    Write-Host "  $($B.MH * 58)" -ForegroundColor DarkGray
    Write-Host ''
}

# ============================================================================
#  MENU
# ============================================================================

function Show-Menu {
    Write-Host '  REPAIR MENU' -ForegroundColor Cyan
    Write-Host "  $($B.H * 62)" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  [1]  * FULL REPAIR (Recommended)' -ForegroundColor Green
    Write-Host '       SFC + conditional DISM + safe caches + network health + disk scan'
    Write-Host ''
    Write-Host '  SYSTEM REPAIR' -ForegroundColor DarkCyan
    Write-Host "  $($B.MH * 40)" -ForegroundColor DarkGray
    Write-Host '  [2]  SFC & DISM System Repair' -ForegroundColor White
    Write-Host '       System file check + component store repair'
    Write-Host '  [3]  Clear All Caches (Safe)' -ForegroundColor White
    Write-Host '       DNS, Temp, Thumbnails - Recycle Bin is opt-in'
    Write-Host '  [4]  Reset Network Stack' -ForegroundColor White
    Write-Host '       Explicit repair; DNS/DoH is backed up and restored'
    Write-Host '  [5]  DISM Deep Component Cleanup' -ForegroundColor White
    Write-Host '       Component cleanup (ResetBase is optional)'
    Write-Host '  [6]  CHKDSK Disk Health Check' -ForegroundColor White
    Write-Host '       Repair-Volume online scan on the Windows drive'
    Write-Host ''
    Write-Host '  WINDOWS UPDATE & STORE' -ForegroundColor DarkCyan
    Write-Host "  $($B.MH * 40)" -ForegroundColor DarkGray
    Write-Host '  [7]  Repair Windows Update' -ForegroundColor White
    Write-Host '       Safely reset WU components (fixes stuck updates)'
    Write-Host '  [13] Windows Update Health Check' -ForegroundColor White
    Write-Host '       Read-only: services, history, connectivity'
    Write-Host '  [10] Reset Windows Store Apps' -ForegroundColor White
    Write-Host '       Re-register Store and AppX packages'
    Write-Host ''
    Write-Host '  DIAGNOSE (READ-ONLY)' -ForegroundColor DarkCyan
    Write-Host "  $($B.MH * 40)" -ForegroundColor DarkGray
    Write-Host '  [12] Quick Health Scan' -ForegroundColor White
    Write-Host '       SFC verify, DISM check, disk, services, Defender'
    Write-Host '  [11] Scan Event Logs for Errors' -ForegroundColor White
    Write-Host '       Recent critical and error events'
    Write-Host '  [14] Network Diagnostics' -ForegroundColor White
    Write-Host '       Adapter, gateway, DNS, and internet tests'
    Write-Host '  [17] Problem Device Scan' -ForegroundColor White
    Write-Host '       Drivers and devices reporting errors'
    Write-Host '  [18] Disk Space Analyzer' -ForegroundColor White
    Write-Host '       What is eating your disk space'
    Write-Host '  [19] Startup Programs Viewer' -ForegroundColor White
    Write-Host '       What launches automatically at sign-in'
    Write-Host ''
    Write-Host '  MORE TOOLS' -ForegroundColor DarkCyan
    Write-Host "  $($B.MH * 40)" -ForegroundColor DarkGray
    Write-Host '  [8]  Create System Restore Point' -ForegroundColor White
    Write-Host '       Snapshot before making changes'
    Write-Host '  [9]  Check Critical Services' -ForegroundColor White
    Write-Host '       Verify essential services, restart stopped ones'
    Write-Host '  [15] Rebuild Icon & Thumbnail Cache' -ForegroundColor White
    Write-Host '       Fixes blank or wrong icons (restarts Explorer)'
    Write-Host '  [16] Repair Time Sync' -ForegroundColor White
    Write-Host '       Wrong clock breaks HTTPS and updates'
    Write-Host '  [21] Fix Performance Counters' -ForegroundColor White
    Write-Host '       Rebuild counter registry (fixes Perflib errors)'
    Write-Host '  [22] Orphaned Service Cleanup' -ForegroundColor White
    Write-Host '       Find services left behind by uninstalled apps'
    Write-Host '  [23] AI Feature Privacy' -ForegroundColor White
    Write-Host '       Reversible Copilot, Recall, Edge and Chrome AI policies'
    Write-Host '  [20] Export HTML Health Report' -ForegroundColor White
    Write-Host '       Styled report, opens in your browser'
    Write-Host ''
    Write-Host '  [0]  EXIT' -ForegroundColor Red
    Write-Host ''
    Write-Host "  $($B.H * 62)" -ForegroundColor DarkGray
    Write-Host ''

    return (Read-Host '  Select an option [0-23]')
}

# ============================================================================
#  REPAIR: SFC SCAN
# ============================================================================

function Invoke-SfcScan {
    param([int]$Step = 0, [int]$Total = 0)

    if ($Total -gt 0) { Write-StepHeader 'SFC - System File Check' $Step $Total }
    else { Write-StepHeader 'SFC - System File Check' }

    Write-Status Info 'Scanning for corrupted or missing system files...'
    Write-Status Info 'This may take 5-15 minutes. Sleep is blocked for this run.'
    Write-Host ''

    Enable-StayAwake
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = [PSCustomObject]@{ ExitCode = 1; Output = '' }
    try {
        $result = Invoke-Native -FilePath 'sfc.exe' -ArgumentList '/scannow'
    } finally {
        $sw.Stop()
        if ($Total -eq 0) { Disable-StayAwake }  # standalone menu item releases; Full Repair holds
    }

    if ($result.ExitCode -eq 0) {
        Write-Status OK 'SFC completed - no integrity violations found.'
        $Script:Results['SFC'] = 'PASS - No violations'
    } elseif ($result.ExitCode -eq 2) {
        Write-Status OK 'SFC found and repaired corrupted files.'
        $Script:Results['SFC'] = 'PASS - Corruptions repaired'
    } elseif ($result.ExitCode -eq 3) {
        Write-Status Fail 'SFC found errors but could NOT fix all of them.'
        $Script:Results['SFC'] = 'WARN - Some files could not be repaired'
        $Script:HasFailure = $true
    } else {
        Write-Status Fail "SFC exited with code $($result.ExitCode)."
        $Script:Results['SFC'] = "FAIL - Exit code $($result.ExitCode)"
        $Script:HasFailure = $true
    }
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  REPAIR: DISM
# ============================================================================

function Invoke-DismRepair {
    param([int]$Step = 0, [int]$Total = 0)

    if ($Total -gt 0) { Write-StepHeader 'DISM - Component Store Repair' $Step $Total }
    else { Write-StepHeader 'DISM - Component Store Repair' }

    Write-Status Info 'Checking CBS log for unrepaired corruption...'

    $cbsPath = "$env:SystemRoot\Logs\CBS\CBS.log"
    $runDism = $false
    if (Test-Path $cbsPath) {
        try {
            # -Tail reads only the end of the file (CBS.log can be hundreds of MB)
            $cbsTail = Get-Content $cbsPath -Tail 300 -EA Stop | Out-String
            if ($cbsTail -match 'Cannot repair|hash mismatch|Repair failed|cannot fix|could not reproject') {
                $runDism = $true
            }
        } catch { $runDism = $true }
    } else { $runDism = $true }

    if ($runDism) {
        Write-Status Info 'Corruption detected. Running DISM /RestoreHealth...'
        Write-Status Info 'Downloads clean files from Windows Update (5-15 min). Sleep blocked.'
        Write-Host ''

        Enable-StayAwake
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $dismResult = Invoke-Native -FilePath 'DISM.exe' -ArgumentList '/Online', '/Cleanup-Image', '/RestoreHealth'

            if ($dismResult.ExitCode -ne 0) {
                Write-Status Warn 'Online repair failed. Trying /LimitAccess (local sources)...'
                $dismResult = Invoke-Native -FilePath 'DISM.exe' -ArgumentList '/Online', '/Cleanup-Image', '/RestoreHealth', '/LimitAccess'
            }
        } finally {
            $sw.Stop()
            if ($Total -eq 0) { Disable-StayAwake }
        }

        if ($dismResult.ExitCode -eq 0) {
            Write-Status OK 'DISM repair succeeded.'
            $Script:Results['DISM'] = 'PASS - Repaired'
        } else {
            Write-Status Fail "DISM failed with exit code $($dismResult.ExitCode)."
            $Script:Results['DISM'] = "FAIL - Exit code $($dismResult.ExitCode)"
            $Script:HasFailure = $true
        }

        if ($dismResult.ExitCode -eq 0) {
            Write-Host ''
            Write-Status Info 'Re-running SFC to verify DISM repairs...'
            $sfcCheck = Invoke-Native -FilePath 'sfc.exe' -ArgumentList '/scannow'
            if ($sfcCheck.ExitCode -eq 0 -or $sfcCheck.ExitCode -eq 2) {
                Write-Status OK 'Post-DISM SFC verification passed.'
                $Script:Results['Post-SFC'] = 'PASS'
            } else {
                Write-Status Warn "Post-DISM SFC exit code: $($sfcCheck.ExitCode)"
                $Script:Results['Post-SFC'] = 'WARN - Some issues remain'
            }
        }

        Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
    } else {
        Write-Status OK 'No unrepaired corruption found in CBS log. DISM skipped.'
        $Script:Results['DISM'] = 'SKIP - Not needed'
    }
}

# ============================================================================
#  REPAIR: CACHE CLEANUP (SAFE - NO WINDOWS UPDATE CACHE DELETION)
# ============================================================================

function Invoke-CacheCleanup {
    param([int]$Step = 0, [int]$Total = 0, [switch]$IncludeRecycleBin)

    if ($Total -gt 0) { Write-StepHeader 'Cache Cleanup (Safe)' $Step $Total }
    else { Write-StepHeader 'Cache Cleanup (Safe)' }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # DNS Flush
    try {
        $null = Invoke-Native-Quiet -FilePath 'ipconfig.exe' -ArgumentList '/flushdns'
        Write-Status OK 'DNS resolver cache flushed.'
    } catch { Write-Status Warn 'DNS flush skipped.' }

    # Temp files (single enumeration; -LiteralPath so files with [] in the
    # name don't get skipped by wildcard expansion)
    $tempPaths = @($env:TEMP, "$env:SystemRoot\Temp")
    foreach ($tp in $tempPaths) {
        try {
            if (Test-Path -LiteralPath $tp) {
                $files = @(Get-ChildItem -LiteralPath $tp -Recurse -File -Force -EA SilentlyContinue)
                $removed = 0
                $freedBytes = [long]0
                foreach ($f in $files) {
                    try {
                        Remove-Item -LiteralPath $f.FullName -Force -EA Stop
                        $removed++
                        $freedBytes += $f.Length
                    } catch { }   # file in use - leave it
                }
                # Remove now-empty subfolders (deepest first)
                Get-ChildItem -LiteralPath $tp -Recurse -Directory -Force -EA SilentlyContinue |
                    Sort-Object { $_.FullName.Length } -Descending |
                    ForEach-Object {
                        if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -EA SilentlyContinue)) {
                            Remove-Item -LiteralPath $_.FullName -Force -EA SilentlyContinue
                        }
                    }
                $freedMB = [math]::Round($freedBytes / 1MB, 1)
                Write-Status OK "Temp files cleaned ($removed of $($files.Count) files, $freedMB MB freed) - $tp"
            }
        } catch { Write-Status Warn "Temp cleanup had errors at $tp (files in use)." }
    }

    # Thumbnail cache
    try {
        $thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        if (Test-Path $thumbPath) {
            $thumbs = Get-ChildItem "$thumbPath\thumbcache_*.db" -EA SilentlyContinue
            if ($thumbs) {
                $thumbs | Remove-Item -Force -EA SilentlyContinue
                Write-Status OK "Thumbnail cache cleared ($($thumbs.Count) files)."
            } else {
                Write-Status OK 'Thumbnail cache already clean.'
            }
        }
    } catch { Write-Status Warn 'Thumbnail cache skipped.' }

    # Recycle Bin is personal data, not a cache required for system repair.
    # It is never emptied by Full Repair and is opt-in for menu option [3].
    if ($IncludeRecycleBin) {
        try {
            Clear-RecycleBin -Force -EA Stop
            Write-Status OK 'Recycle Bin emptied by explicit request.'
        } catch { Write-Status Info 'Recycle Bin already empty or inaccessible.' }
    } else {
        Write-Status Skip 'Recycle Bin preserved.'
    }

    # Delivery Optimization cache (official cmdlet, safe to clear)
    try {
        if (Get-Command Delete-DeliveryOptimizationCache -EA SilentlyContinue) {
            Delete-DeliveryOptimizationCache -Force -EA Stop
            Write-Status OK 'Delivery Optimization cache cleared.'
        }
    } catch { Write-Status Info 'Delivery Optimization cache skipped.' }

    # NOTE: WSReset intentionally NOT run here - it pops the Store window
    # open. Use [10] Reset Windows Store Apps for that.

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"

    # NOTE: Windows Update cache is intentionally NOT cleared here.
    # Deleting SoftwareDistribution\Download breaks in-progress updates
    # and can corrupt the WU database. Use [7] Repair Windows Update instead.

    $Script:Results['Caches'] = 'PASS - Safe caches cleaned (Update data and Recycle Bin preserved unless requested)'
}

# ============================================================================
#  NETWORK STATE BACKUP / NON-DESTRUCTIVE HEALTH REFRESH
# ============================================================================

function Get-StaticNetworkDnsServers {
    param([Parameter(Mandatory)]$Adapter)
    $guid = $Adapter.InterfaceGuid.ToString().Trim('{}')
    $paths = @{
        IPv4 = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{$guid}"
        IPv6 = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\{$guid}"
    }
    $result = [ordered]@{ IPv4 = @(); IPv6 = @() }
    foreach ($family in @('IPv4','IPv6')) {
        $raw = ''
        try { $raw = [string](Get-ItemPropertyValue -LiteralPath $paths[$family] -Name 'NameServer' -EA Stop) } catch { }
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $result[$family] = @($raw -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }
    [PSCustomObject]$result
}

function Backup-NetworkDnsState {
    try {
        $stateRoot = Join-Path $env:ProgramData 'WindowsPCToolkit\PCFixer\NetworkSnapshots'
        if (-not (Test-Path -LiteralPath $stateRoot)) { New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null }
        $adapters = foreach ($adapter in Get-NetAdapter -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.Name -notmatch 'Loopback' }) {
            $dns = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -EA SilentlyContinue
            $static = Get-StaticNetworkDnsServers -Adapter $adapter
            [PSCustomObject]@{
                InterfaceIndex = $adapter.ifIndex
                InterfaceGuid = $adapter.InterfaceGuid.ToString()
                Name = $adapter.Name
                Automatic = (@($static.IPv4).Count -eq 0 -and @($static.IPv6).Count -eq 0)
                StaticIPv4 = @($static.IPv4)
                StaticIPv6 = @($static.IPv6)
                EffectiveIPv4 = @(($dns | Where-Object AddressFamily -eq 2).ServerAddresses | Where-Object { $_ })
                EffectiveIPv6 = @(($dns | Where-Object AddressFamily -eq 23).ServerAddresses | Where-Object { $_ })
            }
        }
        $doh = @()
        if (Get-Command Get-DnsClientDohServerAddress -EA SilentlyContinue) {
            $doh = @(Get-DnsClientDohServerAddress -EA SilentlyContinue | ForEach-Object {
                [PSCustomObject]@{
                    ServerAddress = $_.ServerAddress
                    DohTemplate = $_.DohTemplate
                    AllowFallbackToUdp = [bool]$_.AllowFallbackToUdp
                    AutoUpgrade = [bool]$_.AutoUpgrade
                }
            })
        }
        $snapshot = [PSCustomObject]@{ Schema = 2; Created = (Get-Date).ToString('o'); Adapters = @($adapters); DoH = @($doh) }
        $path = Join-Path $stateRoot ("network_dns_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
        $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        Write-Status OK "DNS/DoH state backed up: $path"
        return $path
    } catch {
        Write-Status Warn "Could not back up DNS state: $_"
        return $null
    }
}

function Restore-NetworkDnsState {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $snapshot = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        foreach ($adapter in @($snapshot.Adapters)) {
            if (-not (Get-NetAdapter -InterfaceIndex ([int]$adapter.InterfaceIndex) -EA SilentlyContinue)) { continue }
            if ($adapter.PSObject.Properties.Name -contains 'Automatic') {
                if ([bool]$adapter.Automatic) {
                    Set-DnsClientServerAddress -InterfaceIndex ([int]$adapter.InterfaceIndex) -ResetServerAddresses -EA Stop
                    Write-Status OK "Restored automatic/DHCP DNS on $($adapter.Name)."
                } else {
                    $addresses = @($adapter.StaticIPv4) + @($adapter.StaticIPv6) | Where-Object { $_ }
                    if ($addresses.Count -eq 0) { throw "Snapshot for $($adapter.Name) says static DNS but contains no static addresses." }
                    Set-DnsClientServerAddress -InterfaceIndex ([int]$adapter.InterfaceIndex) -ServerAddresses $addresses -EA Stop
                    Write-Status OK "Restored static DNS on $($adapter.Name): $($addresses -join ', ')"
                }
            } else {
                $addresses = @($adapter.IPv4) + @($adapter.IPv6) | Where-Object { $_ }
                if ($addresses.Count -gt 0) { Set-DnsClientServerAddress -InterfaceIndex ([int]$adapter.InterfaceIndex) -ServerAddresses $addresses -EA Stop }
                else { Set-DnsClientServerAddress -InterfaceIndex ([int]$adapter.InterfaceIndex) -ResetServerAddresses -EA Stop }
                Write-Status Warn "Restored $($adapter.Name) from a legacy snapshot that did not record DHCP/static mode."
            }
        }
        if (Get-Command Add-DnsClientDohServerAddress -EA SilentlyContinue) {
            foreach ($entry in @($snapshot.DoH)) {
                $current = Get-DnsClientDohServerAddress -ServerAddress $entry.ServerAddress -EA SilentlyContinue
                if (-not $current -or $current.DohTemplate -ne $entry.DohTemplate -or [bool]$current.AllowFallbackToUdp -ne [bool]$entry.AllowFallbackToUdp -or [bool]$current.AutoUpgrade -ne [bool]$entry.AutoUpgrade) {
                    Remove-DnsClientDohServerAddress -ServerAddress $entry.ServerAddress -EA SilentlyContinue
                    Add-DnsClientDohServerAddress -ServerAddress $entry.ServerAddress -DohTemplate $entry.DohTemplate -AllowFallbackToUdp ([bool]$entry.AllowFallbackToUdp) -AutoUpgrade ([bool]$entry.AutoUpgrade) -EA Stop
                }
            }
        }
        Write-Status OK 'Adapter DNS mode and registered DoH templates restored.'
        return $true
    } catch {
        Write-Status Warn "DNS restore had an error: $_"
        return $false
    }
}

function Invoke-NetworkHealthRefresh {
    param([int]$Step = 0, [int]$Total = 0)
    if ($Total -gt 0) { Write-StepHeader 'Network Health + DNS Refresh' $Step $Total }
    else { Write-StepHeader 'Network Health + DNS Refresh' }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-Native-Quiet -FilePath 'ipconfig.exe' -ArgumentList '/flushdns'
    Write-Status OK 'DNS resolver cache flushed. Adapter DNS and DoH settings preserved.'
    $dnsOK = $false; $httpsOK = $false
    try { Resolve-DnsName -Name 'www.microsoft.com' -DnsOnly -EA Stop | Out-Null; $dnsOK = $true; Write-Status OK 'DNS resolution test passed.' }
    catch { Write-Status Warn "DNS resolution test failed: $_" }
    try { $t = Test-NetConnection -ComputerName 'www.microsoft.com' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue; if ($t) { $httpsOK = $true; Write-Status OK 'HTTPS connectivity test passed.' } else { Write-Status Warn 'HTTPS connectivity test failed.' } }
    catch { Write-Status Warn "HTTPS test unavailable: $_" }
    if ($dnsOK -and $httpsOK) { $Script:Results['Network'] = 'PASS - DNS and HTTPS healthy (settings preserved)' }
    else { $Script:Results['Network'] = 'WARN - Network health check needs review' }
    $sw.Stop(); Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  REPAIR: NETWORK RESET (EXPLICIT ONLY)
# ============================================================================

function Invoke-NetworkReset {
    param([int]$Step = 0, [int]$Total = 0, [switch]$SkipFirewall)

    if ($Total -gt 0) { Write-StepHeader 'Network Stack Reset' $Step $Total }
    else { Write-StepHeader 'Network Stack Reset' }

    Write-Host '  !! WARNING: Your network may disconnect briefly.' -ForegroundColor Yellow
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $dnsSnapshot = Backup-NetworkDnsState
    if (-not $dnsSnapshot) {
        Write-Status Fail 'Network reset aborted because DNS/DoH state could not be backed up.'
        $Script:Results['Network'] = 'FAIL - Backup failed; reset not attempted'
        $Script:HasFailure = $true
        $sw.Stop(); Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
        return
    }

    Write-Status Info 'Flushing DNS...'
    $flush = Invoke-Native-Quiet -FilePath 'ipconfig.exe' -ArgumentList '/flushdns'
    if ($flush.ExitCode -eq 0) { Write-Status OK 'DNS flushed.' } else { Write-Status Warn "DNS flush exited with code $($flush.ExitCode)." }

    Write-Status Info 'Resetting Winsock catalog...'
    $winsock = Invoke-Native-Quiet -FilePath 'netsh.exe' -ArgumentList 'winsock', 'reset'
    if ($winsock.ExitCode -eq 0) { Write-Status OK 'Winsock reset.' }
    else {
        Write-Status Fail "Winsock reset failed with exit code $($winsock.ExitCode)."
        $Script:Results['Network'] = 'FAIL - Winsock reset failed'
        $Script:HasFailure = $true
        $sw.Stop(); Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
        return
    }

    Write-Host ''
    Write-Host '  TCP/IP reset is deeper and can remove custom static IP, gateway,' -ForegroundColor Yellow
    Write-Host '  VLAN, VPN, and adapter settings. This tool backs up DNS/DoH only.' -ForegroundColor Yellow
    $tcpChoice = Read-Host '  Also reset the TCP/IP stack? (y/N)'
    $tcpReset = $false
    if ($tcpChoice -eq 'y' -or $tcpChoice -eq 'Y') {
        Write-Status Info 'Resetting TCP/IP stack...'
        $tcp = Invoke-Native-Quiet -FilePath 'netsh.exe' -ArgumentList 'int', 'ip', 'reset'
        if ($tcp.ExitCode -eq 0) { Write-Status OK 'TCP/IP reset.'; $tcpReset = $true }
        else { Write-Status Warn "TCP/IP reset exited with code $($tcp.ExitCode)." }
    } else {
        Write-Status Skip 'TCP/IP reset skipped; custom adapter settings preserved.'
    }

    # Firewall reset deletes ALL custom firewall rules - make it opt-in.
    Write-Host ''
    $fwChoice = 'n'
    if ($SkipFirewall) {
        Write-Status Skip 'Firewall reset skipped.'
    } else {
        Write-Host '  !! Resetting the firewall deletes ALL custom firewall rules' -ForegroundColor Yellow
        Write-Host '  !! (VPN, game, and app rules will need to be re-created).' -ForegroundColor Yellow
        $fwChoice = Read-Host '  Also reset Windows Firewall to defaults? (y/N)'
    }
    $firewallReset = $false
    if ($fwChoice -eq 'y' -or $fwChoice -eq 'Y') {
        $fw = Invoke-Native-Quiet -FilePath 'netsh.exe' -ArgumentList 'advfirewall', 'reset'
        if ($fw.ExitCode -eq 0) { Write-Status OK 'Firewall reset to defaults.'; $firewallReset = $true }
        else { Write-Status Warn "Firewall reset exited with code $($fw.ExitCode)." }
    } else {
        Write-Status Skip 'Firewall reset skipped (custom rules preserved).'
    }

    if (-not (Restore-NetworkDnsState -Path $dnsSnapshot)) {
        Write-Status Fail "DNS/DoH rollback failed. Restore manually from: $dnsSnapshot"
        $Script:Results['Network'] = 'FAIL - Reset ran, but DNS rollback failed'
        $Script:HasFailure = $true
    } else {
        $parts = @('Winsock')
        if ($tcpReset) { $parts += 'TCP/IP' }
        if ($firewallReset) { $parts += 'firewall' }
        $Script:Results['Network'] = "PASS - $($parts -join ' + ') reset; DNS state restored"
    }
    Write-Status Info 'A reboot is required to complete Winsock or TCP/IP reset changes.'
    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  REPAIR: DEEP CLEANUP
# ============================================================================

function Invoke-DeepCleanup {
    param([int]$Step = 0, [int]$Total = 0)

    if ($Total -gt 0) { Write-StepHeader 'DISM - Deep Component Cleanup' $Step $Total }
    else { Write-StepHeader 'DISM - Deep Component Cleanup' }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Status Info 'Analyzing component store...'
    Write-Host ''
    $null = Invoke-Native -FilePath 'DISM.exe' -ArgumentList '/Online', '/Cleanup-Image', '/AnalyzeComponentStore'
    Write-Host ''

    Write-Status Info 'Starting component cleanup...'
    $clean1 = Invoke-Native -FilePath 'DISM.exe' -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup'
    if ($clean1.ExitCode -eq 0) {
        Write-Status OK 'Component cleanup complete.'
    } else {
        Write-Status Warn "Component cleanup exited with code $($clean1.ExitCode)."
    }

    # ResetBase WARNING - this prevents uninstalling recent updates
    Write-Host ''
    Write-Host '  !! WARNING: /ResetBase removes ALL superseded components.' -ForegroundColor Yellow
    Write-Host '  !! This permanently prevents uninstalling recent Windows Updates.' -ForegroundColor Yellow
    Write-Host '  !! This cannot be undone.' -ForegroundColor Yellow
    Write-Host ''
    $rbChoice = Read-Host '  Run ResetBase? (y/N)'
    if ($rbChoice -eq 'y' -or $rbChoice -eq 'Y') {
        Write-Status Info 'Running ResetBase...'
        $clean2 = Invoke-Native -FilePath 'DISM.exe' -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase'
        if ($clean2.ExitCode -eq 0) {
            Write-Status OK 'ResetBase complete - superseded components removed.'
        } else {
            Write-Status Fail "ResetBase exited with code $($clean2.ExitCode)."
            $Script:HasFailure = $true
        }
    } else {
        Write-Status Skip 'ResetBase skipped by user.'
    }

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"

    $Script:Results['DeepClean'] = 'PASS - Component store cleaned'
}

# ============================================================================
#  REPAIR: CHKDSK
# ============================================================================

function Invoke-DiskCheck {
    param([int]$Step = 0, [int]$Total = 0)

    if ($Total -gt 0) { Write-StepHeader 'Disk Health - Online Scan' $Step $Total }
    else { Write-StepHeader 'Disk Health - Online Scan' }

    $driveLetter = $env:SystemDrive.TrimEnd('\').TrimEnd(':')
    Write-Status Info "Running Repair-Volume -Scan on $driveLetter`: (online, no reboot needed)..."
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $usedFallback = $false
    try {
        if (-not (Get-Command Repair-Volume -EA SilentlyContinue)) { throw 'Repair-Volume cmdlet is unavailable.' }
        $rv = Repair-Volume -DriveLetter $driveLetter -Scan -ErrorAction Stop
        $resultText = "$rv"
        if ($resultText -match 'NoErrorsFound') {
            Write-Status OK "Repair-Volume scan: $resultText"
            $Script:Results['Disk'] = 'PASS - No errors'
        } elseif ($resultText -match 'ScanNeeded|SpotFixNeeded|RebootRequired') {
            Write-Status Warn "Repair-Volume scan result: $resultText"
            Write-Status Info "For an offline repair, run: Repair-Volume -DriveLetter $driveLetter -OfflineScanAndFix"
            $Script:Results['Disk'] = "WARN - $resultText"
        } else {
            Write-Status Warn "Repair-Volume returned: $resultText"
            $Script:Results['Disk'] = "WARN - $resultText"
        }
    } catch {
        $usedFallback = $true
        Write-Status Warn "Repair-Volume could not run: $($_.Exception.Message)"
        Write-Status Info 'Falling back to chkdsk /scan...'
        $chk = Invoke-NativeProcessSafe -FilePath 'chkdsk.exe' -ArgumentList "$driveLetter`:", '/scan'
        switch ($chk.ExitCode) {
            0 {
                Write-Status OK 'chkdsk scan completed; no errors were found.'
                $Script:Results['Disk'] = 'PASS - No errors (chkdsk fallback)'
            }
            1 {
                Write-Status Warn 'chkdsk found and fixed file-system errors.'
                $Script:Results['Disk'] = 'WARN - Errors found and fixed by chkdsk'
            }
            2 {
                Write-Status Warn 'chkdsk reported cleanup activity or errors that were not repaired because /f was not used.'
                Write-Status Info "Run: Repair-Volume -DriveLetter $driveLetter -OfflineScanAndFix"
                $Script:Results['Disk'] = 'WARN - Offline repair may be needed'
            }
            3 {
                Write-Status Fail 'chkdsk could not complete the check or could not repair detected errors.'
                Write-Status Info "Run: Repair-Volume -DriveLetter $driveLetter -OfflineScanAndFix"
                $Script:Results['Disk'] = 'FAIL - Disk check incomplete or errors remain'
                $Script:HasFailure = $true
            }
            default {
                Write-Status Fail "Both disk scan paths failed. chkdsk exit code: $($chk.ExitCode)"
                $Script:Results['Disk'] = "FAIL - Repair-Volume and chkdsk failed ($($chk.ExitCode))"
                $Script:HasFailure = $true
            }
        }
    } finally {
        $sw.Stop()
    }
    if ($usedFallback) { Write-Status Info 'Fallback timing is included in the elapsed time.' }
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FEATURE: REPAIR WINDOWS UPDATE (SAFE)
# ============================================================================

function Invoke-WindowsUpdateRepair {
    Write-StepHeader 'Repair Windows Update Components'
    Write-Status Warn 'Use this only when Windows Update is actually stuck or failing.'
    Write-Status Info 'Installed updates are preserved, but rebuilding SoftwareDistribution can reset the visible local update-history list.'
    Write-Host ''

    $pbr = Test-PendingReboot
    if ($pbr.Pending -and ($pbr.Reasons -contains 'Windows Update' -or $pbr.Reasons -contains 'Component Based Servicing')) {
        Write-Status Warn 'An update appears to be mid-install and a reboot is pending.'
        Write-Status Info 'Reboot first. Resetting update caches mid-install can damage servicing state.'
        $Script:Results['WinUpdate'] = 'SKIP - Reboot pending'
        return
    }

    $confirm = Read-Host '  Rebuild Windows Update caches now? (y/N)'
    if ($confirm -notmatch '^[Yy]$') {
        Write-Status Skip 'Windows Update repair cancelled.'
        $Script:Results['WinUpdate'] = 'SKIP - Cancelled'
        return
    }

    Enable-StayAwake
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $services = @('bits','wuauserv','cryptsvc','DoSvc')
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $renamed = @()
    try {
        Write-Status Step 'Stopping update services...'
        foreach ($name in $services) {
            try {
                $svc = Get-Service -Name $name -EA SilentlyContinue
                if ($svc -and $svc.Status -eq 'Running') {
                    Stop-Service -Name $name -Force -EA Stop
                    $svc.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(15))
                }
                Write-Status OK "$name ready."
            } catch { Write-Status Warn "Could not fully stop ${name}: $($_.Exception.Message)" }
        }

        foreach ($folder in @("$env:SystemRoot\SoftwareDistribution", "$env:SystemRoot\System32\catroot2")) {
            if (-not (Test-Path -LiteralPath $folder)) { continue }
            $backup = "$folder.pcfixer.$stamp"
            try {
                Rename-Item -LiteralPath $folder -NewName (Split-Path -Leaf $backup) -EA Stop
                $renamed += $backup
                Write-Status OK "Rebuilt $(Split-Path -Leaf $folder); old cache retained as $(Split-Path -Leaf $backup)."
            } catch {
                Write-Status Warn "Could not rename $(Split-Path -Leaf $folder): $($_.Exception.Message)"
            }
        }

        $null = Invoke-Native-Quiet -FilePath 'ipconfig.exe' -ArgumentList '/flushdns'
        Write-Status OK 'DNS cache refreshed; adapter DNS and DoH settings preserved.'
    } finally {
        Write-Status Step 'Starting update services...'
        foreach ($name in @('cryptsvc','bits','wuauserv','DoSvc')) {
            Start-Service -Name $name -EA SilentlyContinue
            Write-Status OK "$name start requested."
        }
        Disable-StayAwake
        $sw.Stop()
    }

    $uso = Resolve-SystemTool 'UsoClient.exe'
    if ($uso) {
        try { Start-Process -FilePath $uso -ArgumentList 'StartScan' -WindowStyle Hidden -EA SilentlyContinue | Out-Null; Write-Status OK 'Windows Update scan requested.' }
        catch { Write-Status Info 'Open Settings > Windows Update and select Check for updates.' }
    }
    if ($renamed.Count -eq 0) {
        Write-Status Warn 'No update cache folder was rebuilt. Review the log and run the read-only health check.'
        $Script:Results['WinUpdate'] = 'WARN - Cache rebuild incomplete'
    } else {
        Write-Status OK 'Windows Update cache rebuild complete.'
        $Script:Results['WinUpdate'] = 'PASS - Update caches rebuilt'
    }
    Write-Status Info 'Old cache folders are retained for manual recovery and can be deleted later after updates work normally.'
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FEATURE: CREATE SYSTEM RESTORE POINT
# ============================================================================

function Invoke-CreateRestorePoint {
    Write-StepHeader 'Create System Restore Point'

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Enable System Restore if disabled
    try {
        Enable-ComputerRestore -Drive 'C:\' -EA SilentlyContinue
        Write-Status OK 'System Restore enabled on C:.'
    } catch {
        Write-Status Warn 'Could not verify System Restore enablement.'
    }

    Write-Status Info 'Creating restore point (this may take a moment)...'
    try {
        Checkpoint-Computer -Description "PC Fixer v$Script:Version - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType 'MODIFY_SETTINGS' -EA Stop
        Write-Status OK 'System Restore Point created successfully.'
        $Script:Results['RestorePt'] = 'PASS - Restore point created'
    } catch {
        Write-Status Fail "Could not create restore point: $_"
        Write-Status Info 'Note: Windows limits restore points to one per 24 hours by default.'
        $Script:Results['RestorePt'] = 'FAIL - Could not create'
        $Script:HasFailure = $true
    }

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FEATURE: CRITICAL SERVICES HEALTH CHECK
# ============================================================================

function Invoke-ServiceHealthCheck {
    Write-StepHeader 'Critical Services Health Check'

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $criticalServices = @(
        @{ Name = 'wuauserv';     Display = 'Windows Update' },
        @{ Name = 'WinDefend';    Display = 'Windows Defender' },
        @{ Name = 'Dnscache';     Display = 'DNS Client' },
        @{ Name = 'Dhcp';         Display = 'DHCP Client' },
        @{ Name = 'EventLog';     Display = 'Windows Event Log' },
        @{ Name = 'RpcSs';        Display = 'Remote Procedure Call' },
        @{ Name = 'Schedule';     Display = 'Task Scheduler' },
        @{ Name = 'LanmanWorkstation'; Display = 'Workstation' },
        @{ Name = 'BITS';         Display = 'Background Intelligent Transfer' },
        @{ Name = 'CryptSvc';     Display = 'Cryptographic Services' },
        @{ Name = 'MpsSvc';       Display = 'Windows Defender Firewall' },
        @{ Name = 'Spooler';      Display = 'Print Spooler' },
        @{ Name = 'Themes';       Display = 'Themes' },
        @{ Name = 'Audiosrv';     Display = 'Windows Audio' },
        @{ Name = 'Wcmsvc';       Display = 'Windows Connection Manager' },
        @{ Name = 'NlaSvc';       Display = 'Network Location Awareness' },
        @{ Name = 'WSearch';      Display = 'Windows Search' }
    )

    $running = 0
    $stopped = 0
    $issues = @()

    foreach ($svc in $criticalServices) {
        try {
            $service = Get-Service -Name $svc.Name -EA SilentlyContinue
            if ($null -eq $service) { continue }

            if ($service.Status -eq 'Running') {
                Write-Status OK ("{0,-38} Running" -f $svc.Display)
                $running++
            } elseif ($service.StartType -eq 'Disabled') {
                # Deliberately disabled (by the user or a tweak tool) - report
                # it, but don't fight the user's configuration.
                Write-Status Warn ("{0,-38} Disabled (not auto-started)" -f $svc.Display)
            } elseif ($service.StartType -eq 'Manual') {
                # Demand-start services (BITS, etc.) sit stopped by design and
                # Windows launches them when needed - not a problem.
                Write-Status Info ("{0,-38} Stopped (starts on demand)" -f $svc.Display)
            } else {
                # Some services are OK to be stopped
                $okToStop = @('Spooler', 'Themes', 'WSearch')
                if ($svc.Name -in $okToStop) {
                    Write-Status Info ("{0,-38} Stopped (normal)" -f $svc.Display)
                } else {
                    Write-Status Fail ("{0,-38} STOPPED" -f $svc.Display)
                    $issues += $svc.Display
                    $stopped++
                }
            }
        } catch {
            Write-Status Warn ("{0,-38} Could not check" -f $svc.Display)
        }
    }

    Write-Host ''
    Write-Status Info "Results: $running running, $stopped critical services stopped."

    if ($issues.Count -gt 0) {
        Write-Host ''
        Write-Status Warn 'Attempting to start stopped critical services...'
        foreach ($svc in $criticalServices) {
            if ($svc.Display -in $issues) {
                $started = Start-ServiceSafely $svc.Name
                if ($started) {
                    Write-Status OK "$($svc.Display) started."
                } else {
                    Write-Status Fail "Could not start $($svc.Display)."
                }
            }
        }
        $Script:Results['Services'] = "WARN - $stopped stopped (attempted restart)"
    } else {
        Write-Status OK 'All critical services are healthy.'
        $Script:Results['Services'] = 'PASS - All critical services running'
    }

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FEATURE: RESET WINDOWS STORE APPS
# ============================================================================

function Invoke-StoreReset {
    Write-StepHeader 'Reset Windows Store Apps'

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # WSReset first
    Write-Status Info 'Running WSReset (Store cache clear)...'
    try {
        $wsreset = Start-Process -FilePath "$env:SystemRoot\System32\WSReset.exe" -PassThru -Wait -WindowStyle Hidden
        if ($wsreset.ExitCode -eq 0) {
            Write-Status OK 'Windows Store cache reset.'
        } else {
            Write-Status Warn "WSReset exited with code $($wsreset.ExitCode)."
        }
    } catch {
        Write-Status Warn 'WSReset could not run.'
    }

    # Re-register AppX packages
    Write-Host ''
    Write-Status Info 'Re-registering AppX packages (this may take a few minutes)...'
    try {
        $appxPackages = Get-AppxPackage -AllUsers -EA SilentlyContinue
        $count = 0
        $errors = 0
        foreach ($pkg in $appxPackages) {
            try {
                $manifestPath = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
                if (Test-Path $manifestPath) {
                    Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -EA SilentlyContinue | Out-Null
                    $count++
                }
            } catch { $errors++ }
        }
        Write-Status OK "Re-registered $count AppX packages ($errors errors)."
    } catch {
        Write-Status Fail 'Could not enumerate AppX packages.'
    }

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"

    $Script:Results['Store'] = 'PASS - Store apps re-registered'
}

# ============================================================================
#  FEATURE: EVENT LOG ERROR SCAN
# ============================================================================

function Invoke-EventLogScan {
    Write-StepHeader 'Event Log Error Scan'

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Status Info 'Scanning for critical and error events from the last 72 hours...'
    Write-Host ''

    $since = (Get-Date).AddHours(-72)
    $totalErrors = 0
    $totalCritical = 0

    # System log
    Write-Status Step 'System Event Log:'
    try {
        $sysEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            Level = 1,2  # Critical and Error
            StartTime = $since
        } -MaxEvents 20 -EA SilentlyContinue

        if ($sysEvents -and $sysEvents.Count -gt 0) {
            $crit = ($sysEvents | Where-Object { $_.Level -eq 1 }).Count
            $err = ($sysEvents | Where-Object { $_.Level -eq 2 }).Count
            $totalCritical += $crit
            $totalErrors += $err
            Write-Status Warn "$($sysEvents.Count) events ($crit critical, $err errors)"
            Write-Host ''
            foreach ($evt in ($sysEvents | Select-Object -First 8)) {
                $time = $evt.TimeCreated.ToString('MM/dd HH:mm')
                $src = $evt.ProviderName
                $level = if ($evt.Level -eq 1) { 'CRIT' } else { 'ERR ' }
                $msg = if ($evt.Message.Length -gt 80) { $evt.Message.Substring(0, 77) + '...' } else { $evt.Message }
                Write-Host "     [$level] $time | $src" -ForegroundColor $(if ($evt.Level -eq 1) { 'Red' } else { 'Yellow' })
                Write-Host "           $msg" -ForegroundColor DarkGray
            }
        } else {
            Write-Status OK 'No critical/error events in last 72 hours.'
        }
    } catch {
        Write-Status Warn 'Could not read System event log.'
    }

    Write-Host ''

    # Application log
    Write-Status Step 'Application Event Log:'
    try {
        $appEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            Level = 1,2
            StartTime = $since
        } -MaxEvents 20 -EA SilentlyContinue

        if ($appEvents -and $appEvents.Count -gt 0) {
            $crit = ($appEvents | Where-Object { $_.Level -eq 1 }).Count
            $err = ($appEvents | Where-Object { $_.Level -eq 2 }).Count
            $totalCritical += $crit
            $totalErrors += $err
            Write-Status Warn "$($appEvents.Count) events ($crit critical, $err errors)"
            Write-Host ''
            foreach ($evt in ($appEvents | Select-Object -First 8)) {
                $time = $evt.TimeCreated.ToString('MM/dd HH:mm')
                $src = $evt.ProviderName
                $level = if ($evt.Level -eq 1) { 'CRIT' } else { 'ERR ' }
                $msg = if ($evt.Message.Length -gt 80) { $evt.Message.Substring(0, 77) + '...' } else { $evt.Message }
                Write-Host "     [$level] $time | $src" -ForegroundColor $(if ($evt.Level -eq 1) { 'Red' } else { 'Yellow' })
                Write-Host "           $msg" -ForegroundColor DarkGray
            }
        } else {
            Write-Status OK 'No critical/error events in last 72 hours.'
        }
    } catch {
        Write-Status Warn 'Could not read Application event log.'
    }

    Write-Host ''
    Write-Status Info "Summary: $totalCritical critical, $totalErrors errors in last 72 hours."

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"

    if ($totalCritical -gt 0) {
        $Script:Results['EventLog'] = "WARN - $totalCritical critical, $totalErrors errors"
    } elseif ($totalErrors -gt 0) {
        $Script:Results['EventLog'] = "INFO - $totalErrors errors (no critical)"
    } else {
        $Script:Results['EventLog'] = 'PASS - No critical/error events'
    }
}

# ============================================================================
#  FEATURE: QUICK HEALTH SCAN (READ-ONLY)
# ============================================================================

function Invoke-QuickHealthScan {
    Write-StepHeader 'Quick Health Scan (Read-Only)'
    Write-Status Info 'This scan checks system health WITHOUT making any changes.'
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $issues = 0

    # 1. SFC verify-only
    Write-Status Step 'Checking system file integrity (verify only)...'
    $sfcResult = Invoke-Native-Quiet -FilePath 'sfc.exe' -ArgumentList '/verifyonly'
    if ($sfcResult.ExitCode -eq 0) {
        Write-Status OK 'System file integrity OK.'
    } elseif ($sfcResult.ExitCode -eq 2 -or $sfcResult.ExitCode -eq 3) {
        Write-Status Warn 'Integrity violations detected. Run SFC repair [2] to fix.'
        $issues++
    } else {
        Write-Status Info "SFC verify returned code $($sfcResult.ExitCode)."
    }
    Write-Host ''

    # 2. DISM check health
    Write-Status Step 'Checking component store health...'
    $dismResult = Invoke-Native-Quiet -FilePath 'DISM.exe' -ArgumentList '/Online', '/Cleanup-Image', '/CheckHealth'
    if ($dismResult.Output -match 'No component store corruption detected') {
        Write-Status OK 'Component store is healthy.'
    } elseif ($dismResult.Output -match 'repairable|corruption detected') {
        Write-Status Warn 'Component store has repairable corruption. Run DISM repair [2].'
        $issues++
    } else {
        Write-Status Info 'Component store check completed.'
    }
    Write-Host ''

    # 3. Disk space
    Write-Status Step 'Checking disk space...'
    try {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -EA Stop | ForEach-Object {
            $freeGB = [math]::Round($_.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($_.Size / 1GB, 1)
            $pct = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
            $label = $_.DeviceID
            if ($pct -lt 10) {
                Write-Status Fail "$label : $freeGB GB free / $totalGB GB ($pct%) - CRITICALLY LOW"
                $issues++
            } elseif ($pct -lt 20) {
                Write-Status Warn "$label : $freeGB GB free / $totalGB GB ($pct%) - Low"
                $issues++
            } else {
                Write-Status OK "$label : $freeGB GB free / $totalGB GB ($pct%)"
            }
        }
    } catch { Write-Status Warn 'Could not check disk space.' }
    Write-Host ''

    # 4. Pending reboot
    Write-Status Step 'Checking pending reboot status...'
    $pbr = Test-PendingReboot
    if ($pbr.Pending) {
        Write-Status Warn "Reboot pending: $($pbr.Reasons -join ', ')"
        $issues++
    } else {
        Write-Status OK 'No pending reboot.'
    }
    Write-Host ''

    # 5. Critical services
    Write-Status Step 'Quick service check...'
    $criticalSvc = @('wuauserv', 'WinDefend', 'EventLog', 'RpcSs', 'Dnscache')
    $svcIssues = 0
    foreach ($svcName in $criticalSvc) {
        $svc = Get-Service -Name $svcName -EA SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') {
            Write-Status Fail "$svcName ($($svc.DisplayName)) is NOT running."
            $svcIssues++
            $issues++
        }
    }
    if ($svcIssues -eq 0) {
        Write-Status OK 'All critical services running.'
    }
    Write-Host ''

    # 6. Windows Defender
    Write-Status Step 'Checking Windows Defender...'
    try {
        $mp = Get-MpComputerStatus -EA Stop
        if ($mp.AMServiceEnabled) {
            $sigAge = (Get-Date) - $mp.AntivirusSignatureLastUpdated
            if ($sigAge.Days -gt 3) {
                Write-Status Warn "Definitions are $($sigAge.Days) days old. Run Windows Update."
                $issues++
            } else {
                Write-Status OK "Defender active, definitions updated $($sigAge.Days)d ago."
            }
            if ($mp.QuickScanEndTime -and ((Get-Date) - $mp.QuickScanEndTime).Days -gt 7) {
                Write-Status Warn "Last scan was $(((Get-Date) - $mp.QuickScanEndTime).Days) days ago."
            }
        } else {
            Write-Status Fail 'Windows Defender is disabled!'
            $issues++
        }
    } catch { Write-Status Warn 'Could not check Windows Defender status.' }
    Write-Host ''

    # 7. SMART disk health
    Write-Status Step 'Checking disk health (SMART)...'
    try {
        $disks = Get-PhysicalDisk -EA Stop
        foreach ($d in $disks) {
            $health = $d.HealthStatus
            if ($health -eq 'Healthy') {
                Write-Status OK "Disk $($d.DeviceId) ($($d.FriendlyName)): $health"
            } else {
                Write-Status Fail "Disk $($d.DeviceId) ($($d.FriendlyName)): $health"
                $issues++
            }
        }
    } catch { Write-Status Info 'SMART data not available on this system.' }

    $sw.Stop()
    Write-Host ''
    Write-Host "  $($B.H * 62)" -ForegroundColor DarkGray
    if ($issues -eq 0) {
        Write-Status OK 'HEALTH SCAN COMPLETE - No issues found.'
    } else {
        Write-Status Warn "HEALTH SCAN COMPLETE - $issues issue(s) found."
        Write-Status Info 'Consider running the appropriate repair options.'
    }
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"

    $Script:Results['QuickScan'] = if ($issues -eq 0) { 'PASS - Healthy' } else { "WARN - $issues issue(s) found" }
}

# ============================================================================
#  FEATURE: WINDOWS UPDATE HEALTH CHECK (READ-ONLY)
# ============================================================================

function Test-TcpPort {
    param([string]$HostName, [int]$Port = 443, [int]$TimeoutMs = 4000)
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs) -and $client.Connected) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    } catch { return $false } finally {
        if ($null -ne $client) {
            try { $client.Close() } catch { }
            try { $client.Dispose() } catch { }
        }
    }
}

function Invoke-WUHealthCheck {
    Write-StepHeader 'Windows Update Health Check (Read-Only)'
    Write-Status Info 'Verifies Windows Update is healthy WITHOUT changing anything.'
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $issues = 0

    Write-Status Step 'Update services:'
    foreach ($s in @(
        @{ Name = 'wuauserv'; Display = 'Windows Update' },
        @{ Name = 'bits';     Display = 'Background Transfer (BITS)' },
        @{ Name = 'cryptsvc'; Display = 'Cryptographic Services' },
        @{ Name = 'UsoSvc';   Display = 'Update Orchestrator' },
        @{ Name = 'DoSvc';    Display = 'Delivery Optimization' })) {
        $svc = Get-Service -Name $s.Name -EA SilentlyContinue
        if (-not $svc) { Write-Status Warn ("{0,-34} not found" -f $s.Display); continue }
        if ($svc.StartType -eq 'Disabled') {
            Write-Status Fail ("{0,-34} DISABLED (updates will fail)" -f $s.Display)
            $issues++
        } elseif ($svc.Status -eq 'Running') {
            Write-Status OK ("{0,-34} Running" -f $s.Display)
        } else {
            Write-Status Info ("{0,-34} Stopped (starts on demand)" -f $s.Display)
        }
    }
    Write-Host ''

    Write-Status Step 'Update history (registry):'
    $resKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results'
    $anyHistory = $false
    foreach ($k in 'Detect', 'Download', 'Install') {
        $v = (Get-ItemProperty "$resKey\$k" -Name LastSuccessTime -EA SilentlyContinue).LastSuccessTime
        if ($v) { Write-Status Info ("Last successful {0,-8} : {1}" -f $k.ToLower(), $v); $anyHistory = $true }
    }
    if (-not $anyHistory) { Write-Status Info 'No update history recorded in registry.' }
    Write-Host ''

    Write-Status Step 'Pending reboot:'
    $pbr = Test-PendingReboot
    if ($pbr.Pending) {
        Write-Status Warn "Reboot pending ($($pbr.Reasons -join ', ')) - updates pause until reboot."
        $issues++
    } else { Write-Status OK 'No pending reboot.' }
    Write-Host ''

    Write-Status Step 'Disk space for updates:'
    try {
        $sys = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -EA Stop
        $freeGB = [math]::Round($sys.FreeSpace / 1GB, 1)
        if ($freeGB -lt 20) { Write-Status Warn "$freeGB GB free - big feature updates want ~20 GB."; $issues++ }
        else { Write-Status OK "$freeGB GB free." }
    } catch { Write-Status Info 'Could not check disk space.' }
    Write-Host ''

    Write-Status Step 'Connectivity to update servers (TCP 443):'
    foreach ($ep in 'fe2cr.update.microsoft.com', 'dl.delivery.mp.microsoft.com') {
        if (Test-TcpPort -HostName $ep -Port 443) { Write-Status OK $ep }
        else { Write-Status Fail "$ep unreachable"; $issues++ }
    }

    $sw.Stop()
    Write-Host ''
    if ($issues -eq 0) {
        Write-Status OK 'Windows Update looks healthy.'
        $Script:Results['WUHealth'] = 'PASS - Healthy'
    } else {
        Write-Status Warn "$issues issue(s) found. Option [7] repairs WU components."
        $Script:Results['WUHealth'] = "WARN - $issues issue(s)"
    }
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FEATURE: NETWORK DIAGNOSTICS (READ-ONLY)
# ============================================================================

function Invoke-NetworkDiagnostics {
    Write-StepHeader 'Network Diagnostics (Read-Only)'
    Write-Status Info 'Testing adapters, gateway, DNS, and internet - no changes made.'
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $issues = 0

    Write-Status Step 'Network adapters:'
    $up = @()
    try { $up = @(Get-NetAdapter -EA Stop | Where-Object { $_.Status -eq 'Up' }) } catch { }
    if ($up.Count -gt 0) {
        foreach ($a in $up) { Write-Status OK "$($a.Name) - $($a.LinkSpeed) ($($a.InterfaceDescription))" }
    } else { Write-Status Fail 'No active network adapters.'; $issues++ }
    Write-Host ''

    Write-Status Step 'IP configuration:'
    $gw = $null
    try {
        $cfg = Get-NetIPConfiguration -EA Stop |
            Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
            Select-Object -First 1
        if ($cfg) {
            $ip = ($cfg.IPv4Address | Select-Object -First 1).IPAddress
            $gw = ($cfg.IPv4DefaultGateway | Select-Object -First 1).NextHop
            $dnsServers = @($cfg.DNSServer | Where-Object { $_.AddressFamily -eq 2 } |
                ForEach-Object { $_.ServerAddresses }) | Select-Object -First 3
            Write-Status OK "IPv4 address : $ip"
            Write-Status OK "Gateway      : $gw"
            Write-Status Info "DNS servers  : $($dnsServers -join ', ')"
        } else {
            Write-Status Fail 'No IPv4 default gateway - check router / DHCP.'
            $issues++
        }
    } catch { Write-Status Warn 'Could not read IP configuration.' }
    Write-Host ''

    Write-Status Step 'Gateway reachability:'
    if ($gw) {
        if (Test-Connection -ComputerName $gw -Count 2 -Quiet -EA SilentlyContinue) {
            Write-Status OK "Gateway $gw responds to ping."
        } else {
            Write-Status Warn "Gateway $gw not answering ping (some routers block ICMP)."
        }
    } else { Write-Status Skip 'Skipped (no gateway found).' }
    Write-Host ''

    Write-Status Step 'Internet reachability (ping 1.1.1.1):'
    if (Test-Connection -ComputerName '1.1.1.1' -Count 2 -Quiet -EA SilentlyContinue) {
        Write-Status OK 'Internet reachable by IP address.'
    } else { Write-Status Fail 'No reply from 1.1.1.1 - internet may be down.'; $issues++ }
    Write-Host ''

    Write-Status Step 'DNS resolution:'
    try {
        $null = Resolve-DnsName -Name 'www.microsoft.com' -Type A -EA Stop
        Write-Status OK 'DNS resolves www.microsoft.com correctly.'
    } catch {
        Write-Status Fail 'DNS resolution FAILED. Option [4] resets the stack; or set encrypted DNS (DoH).'
        $issues++
    }
    Write-Host ''

    Write-Status Step 'DNS-over-HTTPS (encrypted DNS tunnel):'
    try {
        $enableAuto = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name 'EnableAutoDoh' -EA SilentlyContinue).EnableAutoDoh
        if ($null -eq $enableAuto) {
            Write-Status Info 'EnableAutoDoh not set (Windows default / opportunistic).'
        } elseif ($enableAuto -eq 2) {
            Write-Status OK 'EnableAutoDoh = 2 (prefer/require HTTPS when template known).'
        } elseif ($enableAuto -eq 1) {
            Write-Status Info 'EnableAutoDoh = 1 (opportunistic DoH).'
        } else {
            Write-Status Info "EnableAutoDoh = $enableAuto"
        }
        if (Get-Command Get-DnsClientDohServerAddress -EA SilentlyContinue) {
            $dohList = @(Get-DnsClientDohServerAddress -EA SilentlyContinue)
            if ($dohList.Count -gt 0) {
                foreach ($d in ($dohList | Select-Object -First 6)) {
                    $fb = if ($d.AllowFallbackToUdp) { 'UDP fallback' } else { 'HTTPS only' }
                    Write-Status OK "$($d.ServerAddress) -> $($d.DohTemplate) [$fb]"
                }
            } else {
                Write-Status Info 'No custom DoH templates registered. Run DNS_Set_Quad9_Mullvad.bat for encrypted DNS.'
            }
        } else {
            Write-Status Info 'DoH cmdlets not available on this Windows build (need Win11 / Server 2022+).'
        }
    } catch {
        Write-Status Info 'Could not read DoH status.'
    }
    Write-Host ''

    Write-Status Step 'HTTPS connectivity (TCP 443):'
    if (Test-TcpPort -HostName 'www.microsoft.com' -Port 443) {
        Write-Status OK 'HTTPS connection succeeded.'
    } else { Write-Status Fail 'Could not open an HTTPS connection.'; $issues++ }

    $sw.Stop()
    Write-Host ''
    if ($issues -eq 0) {
        Write-Status OK 'Network looks healthy.'
        $Script:Results['NetDiag'] = 'PASS - Healthy'
    } else {
        Write-Status Warn "$issues issue(s) found. Option [4] resets the network stack."
        $Script:Results['NetDiag'] = "WARN - $issues issue(s)"
    }
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FEATURE: REBUILD ICON & THUMBNAIL CACHE
# ============================================================================

function Invoke-IconCacheRebuild {
    Write-StepHeader 'Rebuild Icon & Thumbnail Cache'
    Write-Status Info 'Fixes blank, black, or wrong icons and thumbnails.'
    Write-Host ''
    Write-Host '  !! Explorer (desktop/taskbar) will close and restart.' -ForegroundColor Yellow
    Write-Host '  !! Open File Explorer windows will be closed.' -ForegroundColor Yellow
    Write-Host ''
    $go = Read-Host '  Continue? (Y/n)'
    if ($go -eq 'n' -or $go -eq 'N') {
        Write-Status Skip 'Icon cache rebuild cancelled.'
        return
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $removed = 0
    try {
        Write-Status Info 'Stopping Explorer...'
        Get-Process -Name explorer -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep -Seconds 2

        $cacheDir = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        foreach ($pattern in 'iconcache_*.db', 'thumbcache_*.db') {
            foreach ($f in (Get-ChildItem -Path (Join-Path $cacheDir $pattern) -Force -EA SilentlyContinue)) {
                try { Remove-Item -LiteralPath $f.FullName -Force -EA Stop; $removed++ } catch { }
            }
        }
        $legacy = "$env:LOCALAPPDATA\IconCache.db"
        if (Test-Path -LiteralPath $legacy) {
            try { Remove-Item -LiteralPath $legacy -Force -EA Stop; $removed++ } catch { }
        }
        Write-Status OK "$removed cache files removed."
    } catch {
        Write-Status Warn "Cache cleanup had errors: $_"
    } finally {
        # Windows 11 sometimes auto-restarts Explorer; only launch it if needed
        # (starting it while the shell is running just opens a folder window).
        Start-Sleep -Seconds 1
        if (-not (Get-Process -Name explorer -EA SilentlyContinue)) {
            Write-Status Info 'Restarting Explorer...'
            Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe')
        }
    }

    Start-Sleep -Seconds 2
    $sw.Stop()
    Write-Status OK 'Explorer is back. Icons/thumbnails will regenerate as you browse.'
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
    $Script:Results['IconCache'] = "PASS - $removed cache files rebuilt"
}

# ============================================================================
#  FEATURE: REPAIR TIME SYNC
# ============================================================================

function Invoke-TimeSyncRepair {
    Write-StepHeader 'Repair Time Synchronization'
    Write-Status Info 'A wrong clock breaks HTTPS, Windows Update, and Store downloads.'
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Status Info ("Current system time : {0}" -f (Get-Date))
    try { Write-Status Info ("Time zone           : {0}" -f (Get-TimeZone).DisplayName) } catch { }
    Write-Host ''

    try {
        $svc = Get-Service -Name W32Time -EA Stop
        if ($svc.StartType -eq 'Disabled') {
            Set-Service -Name W32Time -StartupType Manual -EA Stop
            Write-Status OK 'Windows Time service was Disabled - set back to Manual.'
        }
    } catch { Write-Status Warn 'Could not query the Windows Time service.' }
    if (Start-ServiceSafely 'W32Time') { Write-Status OK 'Windows Time service running.' }
    else { Write-Status Warn 'Could not start the Windows Time service.' }
    Write-Host ''

    Write-Status Step 'Forcing time resync...'
    $r = Invoke-Native-Quiet -FilePath 'w32tm.exe' -ArgumentList '/resync', '/force'
    if ($r.ExitCode -eq 0) {
        Write-Status OK 'Time resynchronized successfully.'
        $Script:Results['TimeSync'] = 'PASS - Resynced'
    } else {
        Write-Status Warn 'Resync failed. Re-registering the time service...'
        $null = Invoke-Native-Quiet -FilePath 'w32tm.exe' -ArgumentList '/unregister'
        $null = Invoke-Native-Quiet -FilePath 'w32tm.exe' -ArgumentList '/register'
        [void](Start-ServiceSafely 'W32Time')
        Start-Sleep -Seconds 2
        $r2 = Invoke-Native-Quiet -FilePath 'w32tm.exe' -ArgumentList '/resync', '/force'
        if ($r2.ExitCode -eq 0) {
            Write-Status OK 'Time service re-registered and resynced.'
            $Script:Results['TimeSync'] = 'PASS - Re-registered + resynced'
        } else {
            Write-Status Fail 'Time sync still failing. Check internet and the BIOS clock/battery.'
            $Script:Results['TimeSync'] = 'FAIL - Resync failed'
            $Script:HasFailure = $true
        }
    }

    Write-Host ''
    Write-Status Step 'Time service status:'
    $status = Invoke-Native-Quiet -FilePath 'w32tm.exe' -ArgumentList '/query', '/status'
    foreach ($ln in ($status.Output -split "`r?`n")) {
        if ($ln -match '^(Source|Last Successful Sync Time|Stratum)') { Write-Status Info $ln.Trim() }
    }

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FEATURE: PROBLEM DEVICE SCAN (READ-ONLY)
# ============================================================================

function Invoke-ProblemDeviceScan {
    Write-StepHeader 'Problem Device Scan (Read-Only)'
    Write-Status Info 'Looking for devices reporting driver or hardware errors...'
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $codeHelp = @{
        1  = 'Device is not configured correctly'
        3  = 'Driver is corrupted or system is low on resources'
        10 = 'Device cannot start (driver problem)'
        12 = 'Not enough free resources (hardware conflict)'
        14 = 'Needs a restart to work properly'
        18 = 'Drivers need to be reinstalled'
        19 = 'Registry configuration is corrupted'
        21 = 'Windows is removing this device'
        22 = 'Device is disabled'
        24 = 'Device not present or drivers missing'
        28 = 'Drivers are not installed'
        31 = 'Windows cannot load the device drivers'
        37 = 'Driver failed to initialize'
        39 = 'Driver is corrupted or missing'
        43 = 'Device reported a problem and was stopped'
        45 = 'Device is not connected'
        52 = 'Driver signature problem'
    }

    try {
        $bad    = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -EA Stop)
        $real   = @($bad | Where-Object { $_.ConfigManagerErrorCode -notin 22, 45 })
        $benign = @($bad | Where-Object { $_.ConfigManagerErrorCode -in 22, 45 })

        if ($real.Count -eq 0) {
            Write-Status OK 'No devices reporting errors.'
            $Script:Results['Devices'] = 'PASS - No problem devices'
        } else {
            foreach ($d in $real) {
                $code = [int]$d.ConfigManagerErrorCode
                $why = if ($codeHelp.ContainsKey($code)) { $codeHelp[$code] } else { "Error code $code" }
                Write-Status Fail "$($d.Name)"
                Write-Host "           Code $code - $why" -ForegroundColor DarkGray
            }
            Write-Host ''
            Write-Status Warn "$($real.Count) device(s) reporting problems."
            Write-Status Info 'Fix: Device Manager > right-click the device > Update driver,'
            Write-Status Info 'or Uninstall device then Action > Scan for hardware changes.'
            $Script:Results['Devices'] = "WARN - $($real.Count) problem device(s)"
        }
        if ($benign.Count -gt 0) {
            Write-Host ''
            Write-Status Info "$($benign.Count) device(s) disabled or disconnected (usually intentional)."
        }
    } catch {
        Write-Status Warn 'Could not enumerate devices.'
        $Script:Results['Devices'] = 'WARN - Scan failed'
    }

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FEATURE: DISK SPACE ANALYZER (READ-ONLY)
# ============================================================================

function Get-FolderSizeBytes {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -EA SilentlyContinue |
                Measure-Object -Property Length -Sum -EA SilentlyContinue).Sum
        if ($null -eq $sum) { $sum = 0 }
        return [long]$sum
    } catch { return $null }
}

function Invoke-DiskSpaceAnalyzer {
    Write-StepHeader 'Disk Space Analyzer (Read-Only)'
    Write-Status Info 'Measuring common space consumers - large folders can take a minute...'
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -EA Stop | ForEach-Object {
            $freeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($_.Size / 1GB, 1)
            $usedPct = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 0)
            Write-Host ("  {0} {1,8} GB free of {2,8} GB  " -f $_.DeviceID, $freeGB, $totalGB) -ForegroundColor White -NoNewline
            Write-Host (Get-UsageBar $usedPct 18) -ForegroundColor DarkCyan -NoNewline
            Write-Host " $usedPct% used" -ForegroundColor Gray
        }
    } catch { }
    Write-Host ''

    Write-Status Step 'Known space consumers:'
    $targets = @(
        @{ Label = 'User temp files';           Path = $env:TEMP },
        @{ Label = 'Windows temp';              Path = "$env:SystemRoot\Temp" },
        @{ Label = 'WU download cache';         Path = "$env:SystemRoot\SoftwareDistribution\Download" },
        @{ Label = 'Delivery Optimization';     Path = "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization" },
        @{ Label = 'Error reports (WER)';       Path = "$env:ProgramData\Microsoft\Windows\WER" },
        @{ Label = 'Previous Windows install';  Path = "$env:SystemDrive\Windows.old" },
        @{ Label = 'Recycle Bin';               Path = "$env:SystemDrive\`$Recycle.Bin" },
        @{ Label = 'Downloads folder';          Path = "$env:USERPROFILE\Downloads" },
        @{ Label = 'Component store (WinSxS)*'; Path = "$env:SystemRoot\WinSxS" }
    )
    $rows = @()
    foreach ($t in $targets) {
        $bytes = Get-FolderSizeBytes $t.Path
        if ($null -ne $bytes) {
            $rows += [PSCustomObject]@{ Label = $t.Label; MB = [math]::Round($bytes / 1MB, 0) }
        }
    }
    foreach ($f in 'hiberfil.sys', 'pagefile.sys', 'swapfile.sys') {
        try {
            $fi = Get-Item -LiteralPath "$env:SystemDrive\$f" -Force -EA Stop
            $rows += [PSCustomObject]@{ Label = $f; MB = [math]::Round($fi.Length / 1MB, 0) }
        } catch { }
    }

    foreach ($r in ($rows | Sort-Object MB -Descending)) {
        $gb = [math]::Round($r.MB / 1024, 2)
        $color = if ($r.MB -gt 10240) { 'Red' } elseif ($r.MB -gt 1024) { 'Yellow' } else { 'Gray' }
        Write-Host ("  {0,-28} {1,10:N0} MB  ({2,7:N2} GB)" -f $r.Label, $r.MB, $gb) -ForegroundColor $color
    }

    Write-Host ''
    Write-Status Info '* WinSxS uses hardlinks; its true disk cost is smaller than shown.'
    Write-Status Info 'hiberfil.sys: remove with "powercfg /h off" (disables hibernate + fast startup).'
    Write-Status Info 'Windows.old: removed via Disk Cleanup > Previous Windows installation(s).'
    Write-Status Info 'Temp/WU/DO caches: option [3] Clear All Caches cleans the safe ones.'

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
    $Script:Results['DiskSpace'] = 'PASS - Analyzed (read-only)'
}

# ============================================================================
#  FEATURE: STARTUP PROGRAMS VIEWER (READ-ONLY)
# ============================================================================

function Invoke-StartupViewer {
    Write-StepHeader 'Startup Programs (Read-Only)'
    Write-Status Info 'Programs that launch automatically when you sign in.'
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $entries = @()

    foreach ($spot in @(
        @{ Src = 'HKLM Run (all users)'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' },
        @{ Src = 'HKLM Run (32-bit)';    Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run' },
        @{ Src = 'HKCU Run (this user)'; Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' },
        @{ Src = 'HKLM RunOnce';         Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' },
        @{ Src = 'HKCU RunOnce';         Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' })) {
        try {
            $key = Get-Item -LiteralPath $spot.Path -EA Stop
            foreach ($name in $key.GetValueNames()) {
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $entries += [PSCustomObject]@{ Source = $spot.Src; Name = $name; Command = [string]$key.GetValue($name) }
            }
        } catch { }
    }

    foreach ($sf in @(
        @{ Src = 'Startup folder (user)'; Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" },
        @{ Src = 'Startup folder (all)';  Path = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" })) {
        Get-ChildItem -LiteralPath $sf.Path -File -EA SilentlyContinue |
            Where-Object { $_.Name -ne 'desktop.ini' } |
            ForEach-Object {
                $entries += [PSCustomObject]@{ Source = $sf.Src; Name = $_.BaseName; Command = $_.FullName }
            }
    }

    if ($entries.Count -eq 0) {
        Write-Status OK 'No startup programs found.'
    } else {
        foreach ($e in ($entries | Sort-Object Source, Name)) {
            $cmd = $e.Command
            if ($cmd.Length -gt 70) { $cmd = $cmd.Substring(0, 67) + '...' }
            if ($e.Command -match '\\AppData\\Local\\Temp\\|\\Windows\\Temp\\') {
                Write-Status Warn "$($e.Name)  [$($e.Source)]  << runs from a TEMP folder - verify this!"
            } else {
                Write-Status Info ("{0,-32} [{1}]" -f $e.Name, $e.Source)
            }
            Write-Host "           $cmd" -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Status Info "$($entries.Count) startup entries found."
        Write-Status Info 'To disable one: Task Manager > Startup apps. This tool is read-only.'
    }

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
    $Script:Results['Startup'] = "PASS - $($entries.Count) entries listed"
}

# ============================================================================
#  FEATURE: EXPORT HTML HEALTH REPORT
# ============================================================================

function ConvertTo-HtmlSafe {
    param([string]$Text)
    return [System.Net.WebUtility]::HtmlEncode("$Text")
}

function Export-HealthReport {
    Write-StepHeader 'Export HTML Health Report'
    Write-Status Info 'Collecting system information...'
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $now = Get-Date

    # --- Gather data (each block independent and failure-tolerant) ---
    $osName = ''; $build = ''; $uptimeStr = ''; $cpuName = ''; $ramStr = ''
    try {
        $os = Get-CimInstance Win32_OperatingSystem -EA Stop
        $osName = $os.Caption; $build = $os.BuildNumber
        $up = $now - $os.LastBootUpTime
        $uptimeStr = "$($up.Days)d $($up.Hours)h $($up.Minutes)m"
        $cs = Get-CimInstance Win32_ComputerSystem -EA Stop
        $totalRam = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        $freeRam  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $ramStr = "$([math]::Round($totalRam - $freeRam, 1)) GB used of $totalRam GB"
    } catch { }
    try { $cpuName = (Get-CimInstance Win32_Processor -EA Stop | Select-Object -First 1).Name -replace '\s+', ' ' } catch { }

    $diskRows = ''
    try {
        foreach ($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -EA Stop)) {
            $freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($d.Size / 1GB, 1)
            $pctFree = [math]::Round(($d.FreeSpace / $d.Size) * 100, 1)
            $cls = if ($pctFree -lt 10) { 'bad' } elseif ($pctFree -lt 20) { 'warn' } else { 'good' }
            $diskRows += "<tr><td>$(ConvertTo-HtmlSafe $d.DeviceID)</td><td>$freeGB GB</td><td>$totalGB GB</td><td class='$cls'>$pctFree% free</td></tr>"
        }
    } catch { }

    $defenderStr = 'Unknown'
    $defenderCls = 'warn'
    try {
        $mp = Get-MpComputerStatus -EA Stop
        if ($mp.AMServiceEnabled) {
            $sigAge = ($now - $mp.AntivirusSignatureLastUpdated).Days
            $defenderStr = "Active - definitions updated ${sigAge}d ago"
            $defenderCls = if ($sigAge -gt 3) { 'warn' } else { 'good' }
        } else { $defenderStr = 'DISABLED'; $defenderCls = 'bad' }
    } catch { }

    $pbr = Test-PendingReboot
    $rebootStr = if ($pbr.Pending) { "PENDING ($(($pbr.Reasons -join ', ')))" } else { 'Not required' }
    $rebootCls = if ($pbr.Pending) { 'warn' } else { 'good' }

    $svcRows = ''
    foreach ($svcDef in @(
        @{ Name = 'wuauserv';  Display = 'Windows Update' },
        @{ Name = 'WinDefend'; Display = 'Microsoft Defender' },
        @{ Name = 'MpsSvc';    Display = 'Defender Firewall' },
        @{ Name = 'Dnscache';  Display = 'DNS Client' },
        @{ Name = 'Dhcp';      Display = 'DHCP Client' },
        @{ Name = 'EventLog';  Display = 'Event Log' },
        @{ Name = 'BITS';      Display = 'BITS Transfer' },
        @{ Name = 'CryptSvc';  Display = 'Cryptographic Services' })) {
        $svc = Get-Service -Name $svcDef.Name -EA SilentlyContinue
        if ($svc) {
            $cls = if ($svc.Status -eq 'Running') { 'good' } else { 'bad' }
            $svcRows += "<tr><td>$(ConvertTo-HtmlSafe $svcDef.Display)</td><td class='$cls'>$($svc.Status)</td></tr>"
        }
    }

    $evtSummary = ''
    try {
        $since = $now.AddHours(-72)
        foreach ($logName in 'System', 'Application') {
            $evts = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 1, 2; StartTime = $since } -MaxEvents 50 -EA SilentlyContinue)
            $cls = if ($evts.Count -gt 10) { 'warn' } else { 'good' }
            $evtSummary += "<tr><td>$logName log</td><td class='$cls'>$($evts.Count) critical/error events (72h)</td></tr>"
        }
    } catch { }

    $resultRows = ''
    if ($Script:Results.Count -gt 0) {
        foreach ($key in $Script:Results.Keys) {
            $val = $Script:Results[$key]
            $cls = if ($val -match 'FAIL') { 'bad' } elseif ($val -match 'WARN|SKIP') { 'warn' } else { 'good' }
            $resultRows += "<tr><td>$(ConvertTo-HtmlSafe $key)</td><td class='$cls'>$(ConvertTo-HtmlSafe $val)</td></tr>"
        }
    } else {
        $resultRows = "<tr><td colspan='2'>No repair operations were run this session.</td></tr>"
    }

    $reportPath = Join-Path $Script:LogDir "PC_Fixer_Report_$($now.ToString('yyyyMMdd_HHmmss')).html"
    $machine = ConvertTo-HtmlSafe $env:COMPUTERNAME

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>PC Health Report - $machine</title>
<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; background: #101418; color: #d7dde3; margin: 0; padding: 24px; }
  .wrap { max-width: 860px; margin: 0 auto; }
  h1 { color: #4fd1ff; font-size: 26px; margin-bottom: 2px; }
  .sub { color: #7a8794; margin-bottom: 24px; font-size: 13px; }
  .card { background: #1a2027; border: 1px solid #2a323c; border-radius: 10px; padding: 18px 20px; margin-bottom: 18px; }
  .card h2 { margin: 0 0 12px; font-size: 15px; color: #9fd9ff; letter-spacing: .06em; text-transform: uppercase; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  td { padding: 6px 8px; border-bottom: 1px solid #232b34; vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  td:first-child { color: #8fa0b0; width: 40%; }
  .good { color: #58d68d; } .warn { color: #f4d03f; } .bad { color: #ec7063; font-weight: 600; }
  .foot { color: #5d6b78; font-size: 12px; margin-top: 20px; text-align: center; }
</style>
</head>
<body>
<div class="wrap">
  <h1>PC Health Report</h1>
  <div class="sub">$machine &middot; generated $(ConvertTo-HtmlSafe ($now.ToString('yyyy-MM-dd HH:mm'))) &middot; PC Corruption Fixer v$Script:Version</div>

  <div class="card"><h2>System</h2><table>
    <tr><td>Computer</td><td>$machine</td></tr>
    <tr><td>OS</td><td>$(ConvertTo-HtmlSafe $osName) (Build $(ConvertTo-HtmlSafe $build))</td></tr>
    <tr><td>CPU</td><td>$(ConvertTo-HtmlSafe $cpuName)</td></tr>
    <tr><td>RAM</td><td>$(ConvertTo-HtmlSafe $ramStr)</td></tr>
    <tr><td>Uptime</td><td>$(ConvertTo-HtmlSafe $uptimeStr)</td></tr>
    <tr><td>Pending reboot</td><td class="$rebootCls">$(ConvertTo-HtmlSafe $rebootStr)</td></tr>
    <tr><td>Microsoft Defender</td><td class="$defenderCls">$(ConvertTo-HtmlSafe $defenderStr)</td></tr>
  </table></div>

  <div class="card"><h2>Drives</h2><table>
    <tr><td><b>Drive</b></td><td><b>Free</b></td><td><b>Total</b></td><td><b>Status</b></td></tr>
    $diskRows
  </table></div>

  <div class="card"><h2>Critical Services</h2><table>$svcRows</table></div>

  <div class="card"><h2>Event Logs</h2><table>$evtSummary</table></div>

  <div class="card"><h2>This Session's Operations</h2><table>$resultRows</table></div>

  <div class="foot">Generated by PC Corruption Fixer v$Script:Version &middot; Log: $(ConvertTo-HtmlSafe $Script:LogPath)</div>
</div>
</body>
</html>
"@

    try {
        $html | Out-File -FilePath $reportPath -Encoding utf8 -ErrorAction Stop
        Write-Status OK "Report saved: $reportPath"
        try {
            Invoke-Item $reportPath
            Write-Status OK 'Report opened in your default browser.'
        } catch { Write-Status Info 'Open the file manually to view it.' }
        $Script:Results['Report'] = 'PASS - HTML report exported'
    } catch {
        Write-Status Fail "Could not save report: $_"
        $Script:Results['Report'] = 'FAIL - Could not save'
        $Script:HasFailure = $true
    }

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FEATURE: FIX PERFORMANCE COUNTERS
# ============================================================================

function Invoke-PerfCounterRepair {
    Write-StepHeader 'Fix Performance Counters'
    Write-Status Info 'Rebuilds the performance counter registry. Fixes Perflib errors'
    Write-Status Info 'in Event Log and broken Performance Monitor / Task Manager graphs.'
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $okAll = $true

    # Microsoft's documented procedure (KB2554336): lodctr /R from System32,
    # then from SysWOW64 for 32-bit counters, then resync WMI. The first
    # lodctr /R attempt sometimes fails and succeeds on retry - a known quirk.
    Write-Status Step 'Rebuilding 64-bit performance counters...'
    Push-Location $Script:Sys32
    try {
        $r = Invoke-Native-Quiet -FilePath 'lodctr.exe' -ArgumentList '/R'
        if ($r.ExitCode -ne 0) {
            Write-Status Info 'First attempt failed (a known quirk) - retrying...'
            Start-Sleep -Seconds 2
            $r = Invoke-Native-Quiet -FilePath 'lodctr.exe' -ArgumentList '/R'
        }
    } finally { Pop-Location }
    if ($r.ExitCode -eq 0) { Write-Status OK '64-bit counters rebuilt from backup store.' }
    else { Write-Status Fail "64-bit rebuild failed (exit $($r.ExitCode))."; $okAll = $false }
    Write-Host ''

    $wow64 = Join-Path $env:SystemRoot 'SysWOW64'
    if (Test-Path -LiteralPath (Join-Path $wow64 'lodctr.exe')) {
        Write-Status Step 'Rebuilding 32-bit performance counters...'
        Push-Location $wow64
        try {
            $r32 = Invoke-Native-Quiet -FilePath 'lodctr.exe' -ArgumentList '/R' -BaseDir $wow64
            if ($r32.ExitCode -ne 0) {
                Start-Sleep -Seconds 2
                $r32 = Invoke-Native-Quiet -FilePath 'lodctr.exe' -ArgumentList '/R' -BaseDir $wow64
            }
        } finally { Pop-Location }
        if ($r32.ExitCode -eq 0) { Write-Status OK '32-bit counters rebuilt.' }
        else { Write-Status Warn "32-bit rebuild failed (exit $($r32.ExitCode))."; $okAll = $false }
        Write-Host ''
    }

    Write-Status Step 'Resyncing WMI performance data...'
    $rs = Invoke-Native-Quiet -FilePath 'winmgmt.exe' -ArgumentList '/resyncperf'
    if ($rs.ExitCode -eq 0) { Write-Status OK 'WMI counters resynced.' }
    else { Write-Status Warn "WMI resync returned exit $($rs.ExitCode)." }

    $sw.Stop()
    Write-Host ''
    if ($okAll) {
        Write-Status OK 'Performance counters rebuilt. A restart completes the repair.'
        $Script:Results['PerfCounters'] = 'PASS - Counters rebuilt'
    } else {
        Write-Status Warn 'Rebuild finished with errors - review the messages above.'
        $Script:Results['PerfCounters'] = 'WARN - Partial rebuild'
    }
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FEATURE: ORPHANED SERVICE CLEANUP
# ============================================================================

function Get-ServiceExePath {
    # Extracts the executable path from a service's PathName command line.
    # Handles: "quoted path" args | unquoted C:\path with spaces\svc.exe args
    param([string]$PathName)
    if ([string]::IsNullOrWhiteSpace($PathName)) { return $null }
    $p = $PathName.Trim() -replace '^\\\?\?\\', ''
    if ($p.StartsWith('"')) {
        $end = $p.IndexOf('"', 1)
        if ($end -gt 1) { return $p.Substring(1, $end - 1) }
        return $null
    }
    $m = [regex]::Match($p, '^(.*?\.exe)(\s|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return ($p -split '\s+')[0]
}

function Invoke-OrphanServiceScan {
    Write-StepHeader 'Orphaned Service Cleanup'
    Write-Status Info 'Finds services whose program no longer exists on disk -'
    Write-Status Info 'dead registrations left behind by uninstalled software.'
    Write-Status Info 'The scan itself changes nothing; removal is optional and asked per service.'
    Write-Host ''

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $services = @()
    try { $services = @(Get-CimInstance Win32_Service -EA Stop) }
    catch {
        Write-Status Warn 'Could not enumerate services.'
        $Script:Results['OrphanSvc'] = 'WARN - Scan failed'
        return
    }

    $orphans = @()
    foreach ($s in $services) {
        $exe = Get-ServiceExePath $s.PathName
        if (-not $exe) { continue }
        $exe = [System.Environment]::ExpandEnvironmentVariables($exe)
        # Only judge absolute paths; anything else can't be checked reliably.
        if (-not [System.IO.Path]::IsPathRooted($exe)) { continue }
        if (-not (Test-Path -LiteralPath $exe)) {
            $orphans += [PSCustomObject]@{
                Name = $s.Name; Display = $s.DisplayName
                Exe = $exe; StartMode = $s.StartMode
            }
        }
    }

    Write-Status Info "$($services.Count) services scanned."
    Write-Host ''

    if ($orphans.Count -eq 0) {
        Write-Status OK 'No orphaned services found - every service binary exists.'
        $Script:Results['OrphanSvc'] = 'PASS - No orphans'
    } else {
        foreach ($o in $orphans) {
            Write-Status Fail "$($o.Name)  ($($o.Display))  [start: $($o.StartMode)]"
            Write-Host "           Missing: $($o.Exe)" -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Status Warn "$($orphans.Count) orphaned service(s) found."
        Write-Status Info 'These cannot run (their program is gone) but still error at boot.'
        Write-Host ''
        $clean = Read-Host '  Remove them? You will be asked for each one separately (y/N)'
        $removed = 0
        if ($clean -eq 'y' -or $clean -eq 'Y') {
            foreach ($o in $orphans) {
                $ans = Read-Host "  Delete service '$($o.Name)' ($($o.Display))? (y/N)"
                if ($ans -eq 'y' -or $ans -eq 'Y') {
                    $del = Invoke-Native-Quiet -FilePath 'sc.exe' -ArgumentList 'delete', $o.Name
                    if ($del.ExitCode -eq 0) {
                        Write-Status OK "Removed $($o.Name)."
                        $removed++
                    } else {
                        Write-Status Fail "Could not remove $($o.Name) (exit $($del.ExitCode))."
                    }
                } else {
                    Write-Status Skip "$($o.Name) kept."
                }
            }
            $Script:Results['OrphanSvc'] = "PASS - $removed of $($orphans.Count) orphan(s) removed"
        } else {
            Write-Status Skip 'No changes made (scan only).'
            $Script:Results['OrphanSvc'] = "WARN - $($orphans.Count) orphan(s) found, none removed"
        }
    }

    $sw.Stop()
    Write-Status Info "Elapsed: $(Get-Elapsed $sw)"
}

# ============================================================================
#  FULL REPAIR ORCHESTRATOR
# ============================================================================

function Invoke-FullRepair {
    Write-StepHeader 'FULL REPAIR - Complete System Fix'
    Write-Status Info 'This will run all standard repair operations.'
    Write-Status Info 'Sleep is blocked for the whole Full Repair (sleep-free).'
    Write-Host ''

    $steps = @(
        @{ Name = 'SFC - System File Check';        Func = 'sfc' },
        @{ Name = 'DISM - Component Store Repair';   Func = 'dism' },
        @{ Name = 'Cache Cleanup (Safe)';            Func = 'caches' },
        @{ Name = 'Network Health + DNS Refresh';      Func = 'networkhealth' },
        @{ Name = 'CHKDSK - Disk Health';            Func = 'chkdsk' }
    )

    # Offer restore point first
    Write-Host ''
    $rpChoice = Read-Host '  Create a System Restore Point first? (Y/n)'
    if ($rpChoice -ne 'n' -and $rpChoice -ne 'N') {
        Invoke-CreateRestorePoint
        Write-Host ''
        Write-Host "  $($B.MH * 62)" -ForegroundColor DarkGray
    }

    Enable-StayAwake
    try {
        $stepNum = 0
        foreach ($step in $steps) {
            $stepNum++
            # Pulse stay-awake between long steps
            Enable-StayAwake
            try {
                switch ($step.Func) {
                    'sfc'     { Invoke-SfcScan -Step $stepNum -Total $steps.Count }
                    'dism'    { Invoke-DismRepair -Step $stepNum -Total $steps.Count }
                    'caches'  { Invoke-CacheCleanup -Step $stepNum -Total $steps.Count }
                    'networkhealth' { Invoke-NetworkHealthRefresh -Step $stepNum -Total $steps.Count }
                    'chkdsk'  { Invoke-DiskCheck -Step $stepNum -Total $steps.Count }
                }
            } catch {
                Write-Status Fail "Unexpected error in $($step.Name): $_"
                $Script:Results[$step.Func] = "FAIL - $_"
                $Script:HasFailure = $true
            }
        }
    } finally {
        Disable-StayAwake
        Write-Status Info 'Stay-awake released (PC may sleep again).'
    }
}

# ============================================================================
#  AI FEATURE PRIVACY - reversible policy manager
# ============================================================================

function Get-AiFeaturePolicyDefinitions {
    @(
        [pscustomobject]@{ Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name='TurnOffWindowsCopilot'; Type='DWord'; Value=1; Label='Legacy Windows Copilot entry points' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name='AllowRecallEnablement'; Type='DWord'; Value=0; Label='Recall optional component availability' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name='DisableAIDataAnalysis'; Type='DWord'; Value=1; Label='Recall snapshot saving' },
        [pscustomobject]@{ Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; Name='DisableAIDataAnalysis'; Type='DWord'; Value=1; Label='Recall snapshot saving for current user' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name='DisableClickToDo'; Type='DWord'; Value=1; Label='Click to Do' },
        [pscustomobject]@{ Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; Name='DisableClickToDo'; Type='DWord'; Value=1; Label='Click to Do for current user' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name='DisableSettingsAgent'; Type='DWord'; Value=1; Label='Settings agentic search' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='CopilotPageContext'; Type='DWord'; Value=0; Label='Edge Copilot page context' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='EdgeEntraCopilotPageContext'; Type='DWord'; Value=0; Label='Edge Entra Copilot page/history context' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='BuiltInAIAPIsEnabled'; Type='DWord'; Value=0; Label='Edge built-in AI APIs' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='AIGenThemesEnabled'; Type='DWord'; Value=0; Label='Edge AI-generated themes' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name='GenAILocalFoundationalModelSettings'; Type='DWord'; Value=1; Label='Edge local GenAI model download' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Google\Chrome'; Name='GenAILocalFoundationalModelSettings'; Type='DWord'; Value=1; Label='Chrome local GenAI model download' }
    )
}

function Get-AiRegistryEntryState {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name)
    $pathExists = Test-Path -LiteralPath $Path
    $valueExists = $false
    $value = $null
    $kind = $null
    if ($pathExists) {
        try {
            $item = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($item.GetValueNames()) -contains $Name) {
                $valueExists = $true
                $value = $item.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $kind = $item.GetValueKind($Name).ToString()
            }
        } catch {}
    }
    [pscustomobject]@{Path=$Path;Name=$Name;PathExisted=[bool]$pathExists;ValueExisted=[bool]$valueExists;Value=$value;Kind=$kind}
}

function New-AiFeatureSnapshot {
    $snapshotRoot = Join-Path $env:ProgramData 'WindowsPCToolkit\PCFixer\AIFeatureSnapshots'
    if (-not (Test-Path -LiteralPath $snapshotRoot)) { New-Item -ItemType Directory -Path $snapshotRoot -Force | Out-Null }
    $entries = foreach ($definition in Get-AiFeaturePolicyDefinitions) {
        Get-AiRegistryEntryState -Path $definition.Path -Name $definition.Name
    }
    $snapshot = [ordered]@{
        Schema = 1
        Created = (Get-Date).ToString('o')
        Computer = $env:COMPUTERNAME
        User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Entries = @($entries)
    }
    $path = Join-Path $snapshotRoot ("ai_features_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    $snapshot | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Get-LatestAiFeatureSnapshot {
    $snapshotRoot = Join-Path $env:ProgramData 'WindowsPCToolkit\PCFixer\AIFeatureSnapshots'
    $file = Get-ChildItem -LiteralPath $snapshotRoot -Filter 'ai_features_*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($file) { return $file.FullName }
    return $null
}

function Restore-AiFeatureSnapshot {
    param([string]$Path)
    if (-not $Path) { $Path = Get-LatestAiFeatureSnapshot }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        Write-Status Warn 'No AI-feature snapshot exists.'
        return $false
    }
    $snapshot = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($entry in @($snapshot.Entries)) {
        if ([bool]$entry.ValueExisted) {
            if (-not (Test-Path -LiteralPath $entry.Path)) { New-Item -Path $entry.Path -Force | Out-Null }
            $propertyType = switch ([string]$entry.Kind) {
                'String'       { 'String' }
                'ExpandString' { 'ExpandString' }
                'MultiString'  { 'MultiString' }
                'Binary'       { 'Binary' }
                'QWord'        { 'QWord' }
                default        { 'DWord' }
            }
            $restoreValue = switch ($propertyType) {
                'Binary'      { [byte[]]@($entry.Value) }
                'MultiString' { [string[]]@($entry.Value) }
                'QWord'       { [uint64]$entry.Value }
                'DWord'       { [uint32]$entry.Value }
                default       { [string]$entry.Value }
            }
            New-ItemProperty -Path $entry.Path -Name $entry.Name -PropertyType $propertyType -Value $restoreValue -Force -ErrorAction Stop | Out-Null
        } else {
            Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
        }
    }
    foreach ($pathState in @($snapshot.Entries | Group-Object Path)) {
        $first = $pathState.Group | Select-Object -First 1
        if (-not [bool]$first.PathExisted -and (Test-Path -LiteralPath $first.Path)) {
            try {
                $item = Get-Item -LiteralPath $first.Path -ErrorAction Stop
                if ($item.ValueCount -eq 0 -and $item.SubKeyCount -eq 0) { Remove-Item -LiteralPath $first.Path -Force -ErrorAction Stop }
            } catch {}
        }
    }
    Write-Status OK ("Exact AI-feature policy state restored from {0}" -f $Path)
    $Script:Results['AI Features'] = 'Previous policy state restored'
    return $true
}

function Set-AiFeaturePrivacyProfile {
    $snapshotPath = New-AiFeatureSnapshot
    Write-Status OK ("Exact registry snapshot saved: {0}" -f $snapshotPath)
    try {
        $changed = 0
        foreach ($definition in Get-AiFeaturePolicyDefinitions) {
            if (-not (Test-Path -LiteralPath $definition.Path)) { New-Item -Path $definition.Path -Force | Out-Null }
            New-ItemProperty -Path $definition.Path -Name $definition.Name -PropertyType $definition.Type -Value $definition.Value -Force -ErrorAction Stop | Out-Null
            $actual = Get-ItemPropertyValue -LiteralPath $definition.Path -Name $definition.Name -ErrorAction Stop
            if ([int64]$actual -ne [int64]$definition.Value) { throw "Verification failed for $($definition.Path)\$($definition.Name)." }
            Write-Status OK ("{0}: policy applied" -f $definition.Label)
            $changed++
        }
        $Script:Results['AI Features'] = "$changed reversible policies applied"
        Write-Status OK 'AI feature privacy profile applied. No services, apps, Search features, or system files were removed.'
        Write-Status Info 'Restart Windows and reopen Edge/Chrome for every policy to take effect.'
        return $true
    } catch {
        $applyError = $_.Exception.Message
        Write-Status Fail ("AI policy application failed: {0}" -f $applyError)
        Write-Status Info 'Rolling back the exact pre-change state...'
        try { Restore-AiFeatureSnapshot -Path $snapshotPath | Out-Null } catch { Write-Status Fail ("Automatic rollback failed: {0}" -f $_.Exception.Message) }
        $Script:HasFailure = $true
        return $false
    }
}

function Invoke-AiFeaturePrivacy {
    Write-StepHeader 'AI Feature Privacy - Reversible Policy Manager'
    Write-Status Info 'Uses documented Windows and browser policy values only.'
    Write-Status Info 'It does not remove AppX packages, disable services, or alter Windows Search.'
    Write-Host ''
    Write-Host '  [1] Apply recommended AI privacy profile' -ForegroundColor White
    Write-Host '  [2] Restore the most recent exact snapshot' -ForegroundColor White
    Write-Host '  [0] Return' -ForegroundColor Gray
    Write-Host ''
    $choice = Read-Host '  Select [0-2]'
    switch ($choice) {
        '1' {
            $confirm = Read-Host '  Apply reversible Copilot, Recall, Edge and Chrome AI policies? (y/N)'
            if ($confirm -match '^[Yy]$') { Set-AiFeaturePrivacyProfile | Out-Null }
            else { Write-Status Skip 'No changes made.' }
        }
        '2' { Restore-AiFeatureSnapshot | Out-Null }
        default { Write-Status Skip 'No changes made.' }
    }
}

# ============================================================================
#  SUMMARY
# ============================================================================

function Show-Summary {
    $w = 64
    $inner = $w - 2
    Write-Host ''
    Write-Host "  $($B.TL)$($B.H * $inner)$($B.TR)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    Write-Host '  REPAIR SUMMARY'.PadRight($inner) -ForegroundColor Green -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.LT)$($B.H * $inner)$($B.RT)" -ForegroundColor Cyan

    if ($Script:Results.Count -eq 0) {
        Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
        Write-Host '  No operations were performed.'.PadRight($inner) -ForegroundColor Gray -NoNewline
        Write-Host "$($B.V)" -ForegroundColor Cyan
    } else {
        foreach ($key in $Script:Results.Keys) {
            $val   = $Script:Results[$key]
            $color = if ($val -match 'FAIL') { 'Red' } elseif ($val -match 'WARN|SKIP') { 'Yellow' } else { 'Green' }
            $line = "  [$key] $val"
            if ($line.Length -gt $inner) { $line = $line.Substring(0, $inner - 3) + '...' }
            Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
            Write-Host $line.PadRight($inner) -ForegroundColor $color -NoNewline
            Write-Host "$($B.V)" -ForegroundColor Cyan
        }
    }

    Write-Host "  $($B.LT)$($B.H * $inner)$($B.RT)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline

    $totalTime = (Get-Date) - $Script:StartTime
    $timeStr = if ($totalTime.TotalHours -ge 1) {
        "  Session time: $([int]$totalTime.TotalHours)h $($totalTime.Minutes)m $($totalTime.Seconds)s"
    } else {
        "  Session time: $($totalTime.Minutes)m $($totalTime.Seconds)s"
    }
    Write-Host $timeStr.PadRight($inner) -ForegroundColor DarkGray -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.V)" -ForegroundColor Cyan -NoNewline
    $logStr = "  Log: $Script:LogPath"
    if ($logStr.Length -gt $inner) { $logStr = $logStr.Substring(0, $inner - 3) + '...' }
    Write-Host $logStr.PadRight($inner) -ForegroundColor DarkGray -NoNewline
    Write-Host "$($B.V)" -ForegroundColor Cyan
    Write-Host "  $($B.BL)$($B.H * $inner)$($B.BR)" -ForegroundColor Cyan

    Write-Host ''
    if (-not $Script:HasFailure -and $Script:Results.Count -gt 0) {
        Write-Host '  [OK] ALL OPERATIONS COMPLETED SUCCESSFULLY' -ForegroundColor Green
    } elseif ($Script:Results.Count -gt 0) {
        Write-Host '  [!!] Some operations had warnings or failures - review the log.' -ForegroundColor Yellow
    }

    # Check if restart is needed
    $pbr = Test-PendingReboot
    if ($pbr.Pending -or $Script:Results.ContainsKey('SFC') -or $Script:Results.ContainsKey('DeepClean')) {
        Write-Host ''
        Write-Host '  ==> RESTART YOUR PC NOW for all changes to take effect.' -ForegroundColor Yellow
    }
    Write-Host ''
}

# ============================================================================
#  MAIN
# ============================================================================

function Main {
    Show-Banner
    Show-Dashboard

    $menuActive = $true
    while ($menuActive) {
        $sel = Show-Menu

        if ($sel -eq '0') { break }

        switch ($sel) {
            '1'  { Invoke-FullRepair }
            '2'  { Invoke-SfcScan; Invoke-DismRepair }
            '3'  { $rb = Read-Host '  Also empty the Recycle Bin? (y/N)'; Invoke-CacheCleanup -IncludeRecycleBin:($rb -match '^[Yy]$') }
            '4'  { Invoke-NetworkReset }
            '5'  { Invoke-DeepCleanup }
            '6'  { Invoke-DiskCheck }
            '7'  { Invoke-WindowsUpdateRepair }
            '8'  { Invoke-CreateRestorePoint }
            '9'  { Invoke-ServiceHealthCheck }
            '10' { Invoke-StoreReset }
            '11' { Invoke-EventLogScan }
            '12' { Invoke-QuickHealthScan }
            '13' { Invoke-WUHealthCheck }
            '14' { Invoke-NetworkDiagnostics }
            '15' { Invoke-IconCacheRebuild }
            '16' { Invoke-TimeSyncRepair }
            '17' { Invoke-ProblemDeviceScan }
            '18' { Invoke-DiskSpaceAnalyzer }
            '19' { Invoke-StartupViewer }
            '20' { Export-HealthReport }
            '21' { Invoke-PerfCounterRepair }
            '22' { Invoke-OrphanServiceScan }
            '23' { Invoke-AiFeaturePrivacy }
            default {
                Write-Host "`n  Invalid selection. Please enter 0-23." -ForegroundColor Red
                Start-Sleep 1
            }
        }

        if ($sel -match '^([1-9]|1[0-9]|2[0-3])$') {
            Write-Host ''
            Read-Host '  Press Enter to return to menu'
        }
    }

    Show-Summary
}

# ============================================================================
#  ENTRY POINT
# ============================================================================

try {
    Main
} catch {
    Write-Host ''
    Write-Host '  [!!] FATAL ERROR:' -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    Write-Host ''
    Write-Host "  Partial log saved to: $Script:LogPath" -ForegroundColor DarkGray
    Write-Host ''
    Read-Host '  Press Enter to exit'
} finally {
    Disable-StayAwake
    try { Stop-Transcript -EA SilentlyContinue } catch { }
}