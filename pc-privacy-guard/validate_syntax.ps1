# Validates PC_Privacy.ps1 for syntax errors.
$target = Join-Path $PSScriptRoot 'PC_Privacy.ps1'
$tokens = $null
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$errs)
if ($errs -and $errs.Count -gt 0) {
    $errs | ForEach-Object { Write-Host "SYNTAX ERROR L$($_.Extent.StartLineNumber): $($_.Message)" }
    exit 1
}
Write-Host "SYNTAX OK - parsed $($tokens.Count) tokens"
exit 0
