# Validates PC_Fixer.ps1 for syntax errors. Portable: works from any folder.
$target = Join-Path $PSScriptRoot 'PC_Fixer.ps1'
$parseErrors = $null
$tokens = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $target -Raw), [ref]$parseErrors)
if ($parseErrors -and $parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Host "SYNTAX ERROR at line $($_.Token.StartLine): $($_.Message)" }
    exit 1
} else {
    Write-Host "SYNTAX OK - No errors found (parsed $($tokens.Count) tokens)"
    exit 0
}
