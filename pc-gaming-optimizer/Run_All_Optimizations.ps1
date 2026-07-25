#requires -version 5.1
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules\Optimizer.Core.psm1') -Force
Initialize-GamingToolkit
Assert-Administrator
Write-GamingHeader
Write-ToolStatus INFO 'Applying only the reversible, evidence-based baseline.'
Invoke-SafeGamingProfile
Show-GpuAudit
Show-NetworkAudit
Show-StorageAudit
Show-MemoryAudit
Show-TimerAudit
Show-DisplayAudit
New-BenchmarkSnapshot
Write-ToolStatus OK 'Safe baseline complete. HAGS, captures, DNS, services, power plan, timers, NIC offloads, and NTFS internals were preserved.'
