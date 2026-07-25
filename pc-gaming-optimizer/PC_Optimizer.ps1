#requires -version 5.1
$ErrorActionPreference='Continue'
Import-Module (Join-Path $PSScriptRoot 'Modules\Optimizer.Core.psm1') -Force
Initialize-GamingToolkit

function Pause-Menu { Write-Host ''; Read-Host '  Press Enter to return to menu' | Out-Null }

while ($true) {
    Write-GamingHeader
    Write-Host ('  HAGS       : {0}' -f (Get-HagsState))
    Write-Host ('  Power plan : {0}' -f (Get-ActivePowerSchemeGuid))
    Write-Host ''
    Write-Host '  SAFE PROFILES' -ForegroundColor Cyan
    Write-Host '  [1] Safe Gaming Profile        Game Mode, optional capture disable'
    Write-Host '  [2] HAGS Manager               Enable, disable, or keep current'
    Write-Host '  [3] Input Profile              Optional mouse acceleration change'
    Write-Host '  [4] Game Session Mode          Above-normal process + stay-awake'
    Write-Host ''
    Write-Host '  DIAGNOSTICS / MAINTENANCE' -ForegroundColor Cyan
    Write-Host '  [5] GPU and Driver Audit       No undocumented driver registry hacks'
    Write-Host '  [6] Network Audit              RSS, RSC, TCP, DNS; read-only'
    Write-Host '  [7] Storage Audit and ReTrim   Official storage tools only'
    Write-Host '  [8] Memory Audit               No standby-list purge'
    Write-Host '  [9] Timer and Boot Audit       No permanent 0.5 ms request'
    Write-Host '  [10] GPU MSI Audit             Read-only safety check'
    Write-Host '  [11] Display Audit             Resolution, refresh, driver'
    Write-Host '  [12] Benchmark Snapshot        JSON evidence for comparisons'
    Write-Host '  [13] Shader Cache Cleanup      Troubleshooting only'
    Write-Host '  [14] PCVR Readiness Audit      HAGS/VBS/timer guidance'
    Write-Host ''
    Write-Host '  REPAIR / PRIVACY' -ForegroundColor Cyan
    Write-Host '  [15] Repair v3.x Tweaks        Remove unsupported legacy overrides'
    Write-Host '  [16] Encrypted DNS Manager     One provider, HTTPS DoH, verification'
    Write-Host '  [17] Open Privacy Guard        Balanced or strict privacy profile'
    Write-Host '  [U] Restore Latest Snapshot    Exact rollback, not guessed defaults' -ForegroundColor Yellow
    Write-Host '  [0] Exit'
    Write-Host ''
    $choice=(Read-Host '  Select').Trim().ToUpperInvariant()
    try {
        switch ($choice) {
            '1' { $cap=Read-Host '  Disable background recording/captures too? (y/N)'; Invoke-SafeGamingProfile -DisableCaptures:($cap -match '^[Yy]$') }
            '2' { Invoke-HagsManager }
            '3' { Invoke-InputProfile }
            '4' { Invoke-GameBooster }
            '5' { Show-GpuAudit }
            '6' { Show-NetworkAudit; $clean=Read-Host '  Remove old v3.x network tweaks now? (y/N)'; if($clean -match '^[Yy]$'){Invoke-LegacyNetworkCleanup} }
            '7' { Show-StorageAudit; $trim=Read-Host '  Run official ReTrim on fixed NTFS volumes? (y/N)'; if($trim -match '^[Yy]$'){Invoke-SafeRetrim} }
            '8' { Show-MemoryAudit }
            '9' { Show-TimerAudit; $clean=Read-Host '  Remove legacy BCD timer overrides? (y/N)'; if($clean -match '^[Yy]$'){Invoke-LegacyTimerCleanup} }
            '10' { Show-GpuMsiAudit }
            '11' { Show-DisplayAudit }
            '12' { New-BenchmarkSnapshot }
            '13' { Invoke-ShaderCacheCleanup }
            '14' { Show-VrAudit }
            '15' { Invoke-LegacyOptimizerRepair }
            '16' { Open-DnsManager }
            '17' { Open-PrivacyGuard }
            'U' { Restore-LatestGamingSnapshot }
            '0' { break }
            default { Write-ToolStatus WARN 'Invalid selection.' }
        }
    } catch { Write-ToolStatus FAIL $_.Exception.Message }
    if ($choice -eq '0') { break }
    Pause-Menu
}
