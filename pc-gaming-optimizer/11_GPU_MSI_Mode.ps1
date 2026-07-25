#requires -version 5.1
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules\Optimizer.Core.psm1') -Force
Initialize-GamingToolkit
try { Show-GpuMsiAudit } catch { Write-ToolStatus FAIL $_.Exception.Message; exit 1 }
