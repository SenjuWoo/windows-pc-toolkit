<#
.SYNOPSIS
    Frees RAM instantly by purging the Windows standby list (cached memory).

.DESCRIPTION
    Uses the real NtSetSystemInformation API - the same mechanism as
    Sysinternals RAMMap's "Empty Standby List". Run right before launching
    a demanding game or AI workload for maximum available memory.

    Note: Windows gives standby memory back to apps automatically anyway;
    purging just makes it available immediately with zero reclaim cost.

.NOTES
    Requires Administrator privileges (SeProfileSingleProcessPrivilege).
#>

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "  >> Free RAM - Purge Standby List" -ForegroundColor Cyan
Write-Host ""

$ramCleanerSource = @'
using System;
using System.Runtime.InteropServices;
public static class RamCleaner
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

    [DllImport("ntdll.dll")]
    public static extern uint NtSetSystemInformation(int infoClass, ref int info, int length);

    public const int SePrivilegeEnabled = 2;
    public const int TokenQuery = 8;
    public const int TokenAdjustPrivileges = 32;
    public const int SystemMemoryListInformation = 80;
    public const int MemoryPurgeStandbyList = 4;
    public const int MemoryPurgeLowPriorityStandbyList = 5;

    public static void EnablePrivilege()
    {
        IntPtr tok = IntPtr.Zero;
        TokPriv1Luid tp;
        tp.Count = 1;
        tp.Luid = 0;
        tp.Attr = SePrivilegeEnabled;
        OpenProcessToken(GetCurrentProcess(), TokenAdjustPrivileges | TokenQuery, ref tok);
        LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", ref tp.Luid);
        AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    }

    public static uint PurgeStandbyList()
    {
        EnablePrivilege();
        int cmd = MemoryPurgeLowPriorityStandbyList;
        NtSetSystemInformation(SystemMemoryListInformation, ref cmd, 4);
        cmd = MemoryPurgeStandbyList;
        return NtSetSystemInformation(SystemMemoryListInformation, ref cmd, 4);
    }
}
'@

try {
    if (-not ("RamCleaner" -as [type])) {
        Add-Type -TypeDefinition $ramCleanerSource -ErrorAction Stop
    }

    $os = Get-CimInstance Win32_OperatingSystem
    $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
    $before  = [math]::Round($os.FreePhysicalMemory / 1024, 0)
    Write-Host "  Free RAM before: $before MB of $totalMB MB" -ForegroundColor Gray

    $status = [RamCleaner]::PurgeStandbyList()
    Start-Sleep -Milliseconds 800

    $after = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024, 0)

    if ($status -eq 0) {
        $freed = $after - $before
        if ($freed -lt 0) { $freed = 0 }
        Write-Host "  Free RAM after:  $after MB" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [ OK ] Standby list purged - freed ~$freed MB" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Purge call returned NTSTATUS $status - are you running as Admin?" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  [FAIL] Could not purge standby list: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  [TIP ] Run this right before launching a game or loading a big AI model." -ForegroundColor Gray
