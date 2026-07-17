<#
.SYNOPSIS
    System benchmark and snapshot tool - captures before/after metrics.

.DESCRIPTION
    Captures key gaming-relevant system metrics:
    - CPU usage, clock speed, temperature (if available)
    - RAM usage and available memory
    - GPU info and VRAM
    - Disk I/O stats
    - Network latency to popular game servers
    - Timer resolution
    - Active services count
    - Background process count

    Saves results to a timestamped file for before/after comparison.

.NOTES
    Run as Administrator for full metrics.
#>

Write-Host ""
Write-Host "  >> SYSTEM BENCHMARK & SNAPSHOT" -ForegroundColor Cyan
Write-Host "  Capturing gaming-relevant system metrics..." -ForegroundColor Gray
Write-Host ""

$results = @()
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$separator = "=" * 60

function Add-Result($Category, $Metric, $Value, $Status = "INFO") {
    $script:results += [PSCustomObject]@{
        Category = $Category
        Metric   = $Metric
        Value    = $Value
        Status   = $Status
    }
}

function Write-Metric($label, $value, $color = "White") {
    Write-Host "    " -NoNewline
    Write-Host "$label : " -ForegroundColor Gray -NoNewline
    Write-Host $value -ForegroundColor $color
}

# ---------------------------------------------------------
# SYSTEM OVERVIEW
# ---------------------------------------------------------
Write-Host "  [1/7] System Overview..." -ForegroundColor Cyan

try {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cpuName = $cpu.Name -replace '\s+', ' '
    Write-Metric "CPU" $cpuName
    Add-Result "System" "CPU" $cpuName

    $cores = $cpu.NumberOfCores
    $threads = $cpu.NumberOfLogicalProcessors
    Write-Metric "Cores/Threads" "$cores cores / $threads threads"
    Add-Result "System" "CPU Cores/Threads" "$cores/$threads"

    $cpuLoad = $cpu.LoadPercentage
    Write-Metric "CPU Load" "$cpuLoad%" $(if($cpuLoad -lt 50){"Green"}elseif($cpuLoad -lt 80){"Yellow"}else{"Red"})
    Add-Result "Performance" "CPU Load" "$cpuLoad%"
}
catch {
    Write-Host "    Could not read CPU info" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# GPU
# ---------------------------------------------------------
Write-Host "  [2/7] GPU Information..." -ForegroundColor Cyan

try {
    # Win32_VideoController.AdapterRAM is a 32-bit field capped at 4GB - read the
    # real VRAM from the display driver key (qwMemorySize is a QWORD)
    $vramRegGB = 0
    try {
        $classKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
        $qw = Get-ChildItem $classKey -ErrorAction SilentlyContinue | ForEach-Object {
            $_.GetValue("HardwareInformation.qwMemorySize")
        } | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
        if ($qw) { $vramRegGB = [math]::Round($qw / 1GB, 1) }
    } catch {}

    Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch "Microsoft Basic|Remote Desktop" } | ForEach-Object {
        $gpuName = $_.Name -replace '\s+', ' '
        Write-Metric "GPU" $gpuName
        Add-Result "System" "GPU" $gpuName

        $vramGB = if ($vramRegGB -gt 0) { $vramRegGB } else { [math]::Round($_.AdapterRAM / 1GB, 1) }
        Write-Metric "VRAM" "$vramGB GB"
        Add-Result "System" "VRAM" "$vramGB GB"

        $gpuStatus = $_.Status
        Write-Metric "Status" $gpuStatus $(if($gpuStatus -eq "OK"){"Green"}else{"Red"})
        Add-Result "System" "GPU Status" $gpuStatus
    }
}
catch {
    Write-Host "    Could not read GPU info" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# RAM
# ---------------------------------------------------------
Write-Host "  [3/7] Memory Status..." -ForegroundColor Cyan

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedGB = [math]::Round($totalGB - $freeGB, 2)
    $usedPct = [math]::Round(($usedGB / $totalGB) * 100, 1)

    Write-Metric "Total RAM" "$totalGB GB"
    Write-Metric "Used" "$usedGB GB ($usedPct%)" $(if($usedPct -lt 70){"Green"}elseif($usedPct -lt 85){"Yellow"}else{"Red"})
    Write-Metric "Available" "$freeGB GB"
    Add-Result "Performance" "RAM Total" "$totalGB GB"
    Add-Result "Performance" "RAM Used" "$usedGB GB ($usedPct%)"
    Add-Result "Performance" "RAM Available" "$freeGB GB"

    # Page file info
    $pageFiles = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
    foreach ($pf in $pageFiles) {
        $pfAlloc = $pf.AllocatedBaseSize
        $pfUsed = $pf.CurrentUsage
        Write-Metric "Page File" "$pfAlloc MB allocated, $pfUsed MB used"
        Add-Result "Performance" "Page File" "$pfAlloc MB / $pfUsed MB used"
    }
}
catch {
    Write-Host "    Could not read memory info" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# DISK
# ---------------------------------------------------------
Write-Host "  [4/7] Disk Performance..." -ForegroundColor Cyan

try {
    Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
        $drive = $_.DeviceID
        $totalGB = [math]::Round($_.Size / 1GB, 1)
        $freeGB = [math]::Round($_.FreeSpace / 1GB, 1)
        $usedPct = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)

        Write-Metric "Drive $drive" "${totalGB}GB total, ${freeGB}GB free ($usedPct% used)" $(if($usedPct -lt 80){"Green"}elseif($usedPct -lt 90){"Yellow"}else{"Red"})
        Add-Result "Storage" "Drive $drive" "${totalGB}GB total, ${freeGB}GB free"
    }

    # Check TRIM status
    $trimStatus = fsutil behavior query DisableDeleteNotify 2>&1
    if ($trimStatus -match "DisableDeleteNotify = 0") {
        Write-Metric "SSD TRIM" "Enabled" "Green"
        Add-Result "Storage" "SSD TRIM" "Enabled"
    } elseif ($trimStatus -match "DisableDeleteNotify = 1") {
        Write-Metric "SSD TRIM" "Disabled (should enable!)" "Red"
        Add-Result "Storage" "SSD TRIM" "Disabled"
    }
}
catch {
    Write-Host "    Could not read disk info" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# NETWORK LATENCY
# ---------------------------------------------------------
Write-Host "  [5/7] Network Latency (ping to game servers)..." -ForegroundColor Cyan

$gameServers = @(
    @{ Name = "Google DNS";      Host = "8.8.8.8" },
    @{ Name = "Cloudflare DNS";  Host = "1.1.1.1" },
    @{ Name = "Microsoft Azure"; Host = "13.107.42.14" }
)

$pingAverages = @()
foreach ($server in $gameServers) {
    try {
        $replies = @(Test-Connection -ComputerName $server.Host -Count 3 -ErrorAction Stop)
        # Windows PowerShell 5.1 exposes ResponseTime; PowerShell 7+ exposes Latency
        $latencyProp = if ($replies[0].PSObject.Properties['Latency']) { 'Latency' } else { 'ResponseTime' }
        $avgMs = [math]::Round(($replies | Measure-Object -Property $latencyProp -Average).Average, 1)
        $color = if($avgMs -lt 20){"Green"}elseif($avgMs -lt 50){"Yellow"}else{"Red"}
        Write-Metric "$($server.Name)" "${avgMs}ms avg" $color
        Add-Result "Network" "$($server.Name) Latency" "${avgMs}ms"
        $pingAverages += $avgMs
    }
    catch {
        Write-Metric "$($server.Name)" "Timeout" "Red"
        Add-Result "Network" "$($server.Name) Latency" "Timeout"
    }
}
Write-Host ""

# ---------------------------------------------------------
# ACTIVE SERVICES & PROCESSES
# ---------------------------------------------------------
Write-Host "  [6/7] System Load..." -ForegroundColor Cyan

try {
    $runningServices = (Get-Service | Where-Object { $_.Status -eq "Running" }).Count
    Write-Metric "Running Services" $runningServices
    Add-Result "System" "Running Services" $runningServices

    $processCount = (Get-Process).Count
    Write-Metric "Running Processes" $processCount
    Add-Result "System" "Running Processes" $processCount

    # Timer resolution
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TimerInfo {
    [DllImport("ntdll.dll")]
    public static extern uint NtQueryTimerResolution(out uint Min, out uint Max, out uint Current);
}
"@ -ErrorAction SilentlyContinue
        $min = 0; $max = 0; $cur = 0
        [TimerInfo]::NtQueryTimerResolution([ref]$min, [ref]$max, [ref]$cur) | Out-Null
        $curMs = [math]::Round($cur / 10000, 2)
        Write-Metric "Timer Resolution" "${curMs}ms" $(if($curMs -le 1){"Green"}else{"Yellow"})
        Add-Result "System" "Timer Resolution" "${curMs}ms"
    }
    catch {}

    # Power plan
    $plan = powercfg /getactivescheme 2>&1
    if ($plan -match '\((.+?)\)') {
        $planName = $matches[1]
        Write-Metric "Power Plan" $planName $(if($planName -match "Ultimate|High"){"Green"}else{"Yellow"})
        Add-Result "System" "Power Plan" $planName
    }
}
catch {
    Write-Host "    Could not read system load" -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------
# GAMING OPTIMIZATION STATUS
# ---------------------------------------------------------
Write-Host "  [7/8] Gaming Optimization Status..." -ForegroundColor Cyan

$checks = @(
    @{ Name = "Game Mode";       Path = "HKCU:\Software\Microsoft\GameBar"; Value = "AllowAutoGameMode"; Expected = 1 },
    @{ Name = "HAGS";            Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; Value = "HwSchMode2"; Expected = 2 },
    @{ Name = "Game DVR Off";    Path = "HKCU:\System\GameConfigStore"; Value = "GameDVR_Enabled"; Expected = 0 },
    @{ Name = "Power Throttle Off"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"; Value = "PowerThrottlingOff"; Expected = 1 }
)

foreach ($check in $checks) {
    try {
        $regVal = (Get-ItemProperty -Path $check.Path -Name $check.Value -ErrorAction SilentlyContinue).($check.Value)
        if ($null -eq $regVal) {
            Write-Metric $check.Name "Not configured" "Yellow"
            Add-Result "Gaming" $check.Name "Not configured"
        } elseif ($regVal -eq $check.Expected) {
            Write-Metric $check.Name "Optimized" "Green"
            Add-Result "Gaming" $check.Name "Optimized"
        } else {
            Write-Metric $check.Name "Not optimized (value: $regVal)" "Yellow"
            Add-Result "Gaming" $check.Name "Default ($regVal)"
        }
    }
    catch {
        Write-Metric $check.Name "Check failed" "Yellow"
        Add-Result "Gaming" $check.Name "Unknown"
    }
}
Write-Host ""

# ---------------------------------------------------------
# 8. DISPLAY & GPU READINESS (Refresh, VRR, ReBAR, Driver)
# ---------------------------------------------------------
Write-Host "  [8/8] Display & GPU Gaming Readiness..." -ForegroundColor Cyan

# Refresh rate check
try {
    $gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch "Microsoft Basic|Remote Desktop|Virtual Desktop" }
    foreach ($gpu in $gpus) {
        $curHz = $gpu.CurrentRefreshRate
        $maxHz = $gpu.MaxRefreshRate
        if ($curHz -and $curHz -gt 0) {
            $hzColor = if ($curHz -ge 120) { "Green" } elseif ($curHz -ge 60) { "Yellow" } else { "Red" }
            $hzStatus = if ($maxHz -and $maxHz -gt $curHz) { "NOT AT MAX ($maxHz Hz available!)" } else { "at maximum" }
            Write-Metric "Refresh Rate" "$curHz Hz ($hzStatus)" $hzColor
            Add-Result "Display" "Refresh Rate" "$curHz Hz ($hzStatus)"
        }
    }
} catch { Write-Metric "Refresh Rate" "Could not detect" "Yellow" }

# GPU driver version
try {
    $classKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    $nvidiaAd = Get-ChildItem $classKey -EA SilentlyContinue | Where-Object { $_.GetValue("DriverDesc") -like "*NVIDIA*" } | Select-Object -First 1
    if ($nvidiaAd) {
        $drv = $nvidiaAd.GetValue("DriverVersion")
        if ($drv) {
            Write-Metric "GPU Driver" "$drv" "Green"
            Add-Result "Display" "GPU Driver" "$drv"
        }
    }
} catch {}

# ReBAR GPU support check
try {
    $nvidiaAd2 = Get-ChildItem $classKey -EA SilentlyContinue | Where-Object { $_.GetValue("DriverDesc") -like "*NVIDIA*" } | Select-Object -First 1
    if ($nvidiaAd2) {
        $rmGpuId = $nvidiaAd2.GetValue("RMGpuId")
        if ($rmGpuId -is [int] -and $rmGpuId -ge 0x2000) {
            Write-Metric "ReBAR GPU Support" "Yes (RTX 30/40 series)" "Green"
            Write-Metric "ReBAR Status" "Check NVIDIA CP > System Info" "Yellow"
            Add-Result "Display" "ReBAR" "GPU supports, check BIOS"
        } else {
            Write-Metric "ReBAR" "Check in NVIDIA Control Panel" "Yellow"
        }
    }
} catch {}

# Focus Assist check
try {
    $focusKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    if (Test-Path $focusKey) {
        $focusAllowCrit = (Get-ItemProperty -Path $focusKey -Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL" -EA SilentlyContinue).NOC_GLOBAL_SETTING_ALLOW_CRITICAL
        if ($focusAllowCrit -eq 1) {
            Write-Metric "Focus Assist" "Enabled for gaming" "Green"
            Add-Result "Gaming" "Focus Assist" "Enabled"
        } else {
            Write-Metric "Focus Assist" "Not configured" "Yellow"
            Add-Result "Gaming" "Focus Assist" "Not configured"
        }
    }
} catch {}

# G-SYNC / FreeSync indicator
try {
    $nvidiaAd3 = Get-ChildItem $classKey -EA SilentlyContinue | Where-Object { $_.GetValue("DriverDesc") -like "*NVIDIA*" } | Select-Object -First 1
    if ($nvidiaAd3) {
        Write-Metric "G-SYNC Capable" "Yes (NVIDIA GPU detected)" "Green"
        Write-Metric "G-SYNC Active" "Verify in NVIDIA Control Panel" "Yellow"
        Add-Result "Display" "G-SYNC" "Capable, verify in NVCP"
    }
} catch {}

# XMP / EXPO reminder (can't detect from OS)
Write-Metric "XMP/EXPO (RAM)" "Check in BIOS - can't detect from Windows" "Yellow"
Add-Result "Display" "XMP/EXPO" "Check in BIOS"
Write-Host ""

# ---------------------------------------------------------
# SAVE RESULTS
# ---------------------------------------------------------
Write-Host $separator -ForegroundColor DarkGray
Write-Host "  BENCHMARK COMPLETE" -ForegroundColor Cyan
Write-Host $separator -ForegroundColor DarkGray
Write-Host ""

$reportDir = Join-Path $PSScriptRoot "Benchmark_Reports"
if (-not (Test-Path $reportDir)) { New-Item -Path $reportDir -ItemType Directory | Out-Null }

$reportFile = Join-Path $reportDir "benchmark_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

$reportContent = @"
PC Gaming Optimizer - System Benchmark Report
$separator
Date: $timestamp
$separator

"@

$categories = $results | Group-Object Category
foreach ($cat in $categories) {
    $reportContent += "`n[$($cat.Name)]`n"
    foreach ($item in $cat.Group) {
        $reportContent += "  $($item.Metric): $($item.Value)`n"
    }
}

$reportContent += "`n$separator`nEnd of Report`n"

$reportContent | Out-File -FilePath $reportFile -Encoding UTF8

# ---------------------------------------------------------
# JSON SNAPSHOT + AUTOMATIC BEFORE/AFTER COMPARISON
# ---------------------------------------------------------
$snapshot = [ordered]@{
    Timestamp         = $timestamp
    CpuLoadPct        = if ($null -ne $cpuLoad)         { [double]$cpuLoad }        else { $null }
    FreeRamGB         = if ($null -ne $freeGB)          { [double]$freeGB }         else { $null }
    RunningServices   = if ($null -ne $runningServices) { [int]$runningServices }   else { $null }
    RunningProcesses  = if ($null -ne $processCount)    { [int]$processCount }      else { $null }
    TimerResolutionMs = if ($null -ne $curMs)           { [double]$curMs }          else { $null }
    AvgPingMs         = if ($pingAverages.Count -gt 0)  { [math]::Round(($pingAverages | Measure-Object -Average).Average, 1) } else { $null }
}

# Compare against the most recent previous snapshot (before saving the new one)
$prevFile = Get-ChildItem $reportDir -Filter "benchmark_*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($prevFile) {
    $prev = $null
    try { $prev = Get-Content $prevFile.FullName -Raw | ConvertFrom-Json } catch {}
    if ($prev) {
        Write-Host "  COMPARED TO PREVIOUS SNAPSHOT ($($prev.Timestamp)):" -ForegroundColor Cyan
        $compareMetrics = @(
            @{ Key = "FreeRamGB";         Label = "Free RAM (GB)";     HigherIsBetter = $true },
            @{ Key = "CpuLoadPct";        Label = "CPU Load (%)";      HigherIsBetter = $false },
            @{ Key = "RunningServices";   Label = "Running Services";  HigherIsBetter = $false },
            @{ Key = "RunningProcesses";  Label = "Running Processes"; HigherIsBetter = $false },
            @{ Key = "TimerResolutionMs"; Label = "Timer Res (ms)";    HigherIsBetter = $false },
            @{ Key = "AvgPingMs";         Label = "Avg Ping (ms)";     HigherIsBetter = $false }
        )
        foreach ($m in $compareMetrics) {
            $old = $prev.($m.Key)
            $new = $snapshot[$m.Key]
            if ($null -eq $old -or $null -eq $new) { continue }
            $delta = [math]::Round($new - $old, 2)
            $improved = if ($m.HigherIsBetter) { $delta -gt 0 } else { $delta -lt 0 }
            $deltaText = if ($delta -gt 0) { "+$delta" } elseif ($delta -lt 0) { "$delta" } else { "no change" }
            $color = if ($delta -eq 0) { "DarkGray" } elseif ($improved) { "Green" } else { "Yellow" }
            Write-Host ("    {0,-20} {1,10}  ->  {2,-10} ({3})" -f $m.Label, $old, $new, $deltaText) -ForegroundColor $color
        }
        Write-Host ""
    }
}

$jsonFile = [System.IO.Path]::ChangeExtension($reportFile, "json")
$snapshot | ConvertTo-Json | Out-File -FilePath $jsonFile -Encoding UTF8

Write-Host "  Results saved to:" -ForegroundColor Gray
Write-Host "    $reportFile" -ForegroundColor White
Write-Host ""
if (-not $prevFile) {
    Write-Host "  Run this again AFTER optimization - it will auto-compare with this snapshot!" -ForegroundColor Yellow
    Write-Host ""
}