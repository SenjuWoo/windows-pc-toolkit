#requires -version 5.1
param([string[]]$ActionIds,[switch]$Preview,[switch]$DebugLog)
$ErrorActionPreference='Stop'
if ($DebugLog) { $env:WINDOWS_PC_TOOLKIT_DEBUG='1' }
Import-Module (Join-Path $PSScriptRoot 'Modules\Toolkit.Core.psm1') -Force -DisableNameChecking
Write-SuiteDiagnostic 'CLI startup' "DataRoot=$(Get-SuiteDataRoot); Preview=$Preview; Debug=$($env:WINDOWS_PC_TOOLKIT_DEBUG -eq '1')"
if ($Preview) { Get-SuitePreview -ActionIds $ActionIds | Format-Table Action,Category,Details -Wrap; exit 0 }
if ($null -eq $ActionIds) { $ActionIds=@(Get-SuiteActionCatalog | Where-Object Default | ForEach-Object Id) }
$apps=@()
if ($ActionIds -contains 'Debloat') { $apps=@(Get-SuiteAppCatalog) }
if ($apps.Count) {
    Write-Host 'Consumer apps to remove (package backups saved first; app data may be deleted):'
    $apps | Format-Table Name,Version
    if ((Read-Host 'Optimize and remove these apps? Type YES to continue') -cne 'YES') { Write-Host 'Canceled. No changes applied.'; exit 0 }
}
$run=Invoke-SuiteRun -ActionIds $ActionIds -AppIds @($apps | ForEach-Object Id) -Progress {param($run) Write-Host $run.Message}
$run.Steps | Format-Table Action,Status,Message -Wrap
Write-Host $run.Message
if ($run.Status -ne 'Completed') { exit 1 }
