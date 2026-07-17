<#
.SYNOPSIS
    GAME BOOSTER - one-shot pre-game boost that HOLDS its optimizations
    for the whole gaming session.

.DESCRIPTION
    Run this right before launching a game. It:
      1. Purges the RAM standby list (instant free memory for the game)
      2. Flushes the DNS cache (fresh server lookups)
      3. Requests 0.5ms system timer resolution and KEEPS HOLDING IT
         until you press a key - unlike a normal script, the request
         stays active because this process stays alive.

    Keep this window open (minimized is fine) while gaming.
    Press any key in this window when done to release the timer.

.NOTES
    Requires Administrator privileges.
#>

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "  >> GAME BOOSTER - PRE-GAME SESSION MODE" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------
# NATIVE API HELPERS
# ---------------------------------------------------------
$boosterSource = @'
using System;
using System.Runtime.InteropServices;
public static class GameBooster
{
    [StructLayout(LayoutKind.Sequential)]
    public struct TokPriv1Luid { public int Count; public long Luid; public int Attr; }

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);

    [DllImport("ntdll.dll")]
    public static extern uint NtSetSystemInformation(int infoClass, ref int info, int length);

    [DllImport("ntdll.dll")]
    public static extern uint NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution);

    [DllImport("ntdll.dll")]
    public static extern uint NtQueryTimerResolution(out uint Min, out uint Max, out uint Current);

    public const uint ES_CONTINUOUS = 0x80000000;
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
    public const uint ES_DISPLAY_REQUIRED = 0x00000002;
    public const uint ES_AWAYMODE_REQUIRED = 0x00000040;

    public static void PreventSleep() {
        // Keep system + display awake while this window holds the game session
        SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED | ES_AWAYMODE_REQUIRED);
    }
    public static void AllowSleep() {
        SetThreadExecutionState(ES_CONTINUOUS);
    }

    public static uint PurgeStandbyList()
    {
        IntPtr tok = IntPtr.Zero;
        TokPriv1Luid tp;
        tp.Count = 1;
        tp.Luid = 0;
        tp.Attr = 2; // SE_PRIVILEGE_ENABLED
        OpenProcessToken(GetCurrentProcess(), 32 | 8, ref tok);
        LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", ref tp.Luid);
        AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        int cmd = 5; // MemoryPurgeLowPriorityStandbyList
        NtSetSystemInformation(80, ref cmd, 4);
        cmd = 4;     // MemoryPurgeStandbyList
        return NtSetSystemInformation(80, ref cmd, 4);
    }
}
'@
if (-not ("GameBooster" -as [type])) {
    Add-Type -TypeDefinition $boosterSource -ErrorAction Stop
}

# Block modern standby / screen-off while the booster session is active
try { [GameBooster]::PreventSleep() } catch { }

# ---------------------------------------------------------
# 1. PURGE RAM STANDBY LIST
# ---------------------------------------------------------
Write-Host "  [1/3] Purging RAM standby list..." -ForegroundColor Cyan
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $before = [math]::Round($os.FreePhysicalMemory / 1024, 0)
    $status = [GameBooster]::PurgeStandbyList()
    Start-Sleep -Milliseconds 600
    $after = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024, 0)
    if ($status -eq 0) {
        $freed = [math]::Max(0, $after - $before)
        Write-Host "    Freed ~$freed MB  (free RAM: $before MB -> $after MB)" -ForegroundColor Green
    } else {
        Write-Host "    Purge returned NTSTATUS $status" -ForegroundColor Yellow
    }
} catch {
    Write-Host "    Could not purge standby list: $_" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# 2. FLUSH DNS CACHE
# ---------------------------------------------------------
Write-Host "  [2/3] Flushing DNS cache..." -ForegroundColor Cyan
ipconfig /flushdns 2>&1 | Out-Null
Write-Host "    DNS cache flushed (fresh game-server lookups)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 3. HOLD 0.5ms TIMER RESOLUTION FOR THE SESSION
# ---------------------------------------------------------
Write-Host "  [3/3] Requesting 0.5ms timer resolution..." -ForegroundColor Cyan
$actualRes = 0
$result = [GameBooster]::NtSetTimerResolution(5000, $true, [ref]$actualRes)
if ($result -eq 0) {
    $actualMs = [math]::Round($actualRes / 10000, 2)
    Write-Host "    Timer resolution: ${actualMs}ms - HELD while this window stays open" -ForegroundColor Green
} else {
    Write-Host "    NtSetTimerResolution returned NTSTATUS: $result" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "  ================================================" -ForegroundColor Green
Write-Host "   GAME SESSION ACTIVE - launch your game now!" -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Keep this window open (minimized is fine) while gaming." -ForegroundColor Gray
Write-Host "  Press ANY KEY here when you're done to release the timer." -ForegroundColor Yellow
Write-Host ""

$sessionStart = Get-Date
$lastAwakePulse = Get-Date
try {
    while (-not [Console]::KeyAvailable) {
        # Re-assert stay-awake periodically (some power policies clear the flag)
        if (((Get-Date) - $lastAwakePulse).TotalSeconds -ge 45) {
            try { [GameBooster]::PreventSleep() } catch { }
            $lastAwakePulse = Get-Date
        }
        Start-Sleep -Milliseconds 300
    }
    [Console]::ReadKey($true) | Out-Null
} catch {
    # Console input redirected (e.g. some hosts) - fall back to Enter
    Read-Host "  Press Enter to end the game session" | Out-Null
} finally {
    # Release the timer request cleanly + allow sleep again
    $actualRes = 0
    try { [GameBooster]::NtSetTimerResolution(5000, $false, [ref]$actualRes) | Out-Null } catch { }
    try { [GameBooster]::AllowSleep() } catch { }
}

$elapsed = (Get-Date) - $sessionStart
$hrs = [int][math]::Floor($elapsed.TotalHours)
Write-Host ""
Write-Host ("  Session ended after {0}h {1:mm}m {1:ss}s - timer + stay-awake released." -f $hrs, $elapsed) -ForegroundColor Cyan
Write-Host "  GG! Run Game Booster again before your next session." -ForegroundColor Gray
Write-Host ""
