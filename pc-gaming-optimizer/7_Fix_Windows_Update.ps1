#requires -version 5.1
$suiteRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$target=$null
foreach($relative in @('Pc Corruption Fixer\PC_Fixer.ps1','pc-corruption-fixer\PC_Fixer.ps1')){
    $candidate=[IO.Path]::GetFullPath((Join-Path $suiteRoot $relative))
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$target=$candidate;break}
}
if($target){
    Write-Host 'Opening PC Corruption Fixer. Use Windows Update Health Check first, then Repair Windows Update only when needed.' -ForegroundColor Cyan
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $target
}else{ Write-Error 'PC Corruption Fixer was not found beside this folder.' }
