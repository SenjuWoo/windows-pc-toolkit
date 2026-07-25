param([string]$Path=(Join-Path $PSScriptRoot 'PC_Fixer.ps1'))
$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){$errors|Format-List Message,Extent;exit 1}
Write-Host "Syntax OK: $Path" -ForegroundColor Green
