#requires -version 5.1
param([string[]]$ActionIds,[switch]$Preview)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules\Toolkit.Core.psm1') -Force -DisableNameChecking
if ($Preview) { Get-SuitePreview -ActionIds $ActionIds | Format-Table Action,Category,Details -Wrap; exit 0 }
$run=Invoke-SuiteRun -ActionIds $ActionIds -Progress {param($run) Write-Host $run.Message}
$run.Steps | Format-Table Action,Status,Message -Wrap
Write-Host $run.Message
if ($run.Status -ne 'Completed') { exit 1 }
