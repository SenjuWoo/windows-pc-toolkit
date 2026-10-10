#requires -version 5.1
param([string]$ExpectedUserSid)
if ($ExpectedUserSid -and $ExpectedUserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
    Write-Error 'Elevation switched Windows accounts. Launch from an administrator account belonging to the intended user.'
    exit 1
}
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules\Optimizer.Core.psm1') -Force
Initialize-GamingToolkit
try { Show-VrAudit } catch { Write-ToolStatus FAIL $_.Exception.Message; exit 1 }
