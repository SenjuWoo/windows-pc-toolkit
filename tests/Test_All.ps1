#requires -version 5.1
$ErrorActionPreference='Stop'
foreach ($test in @('Test_OneDrive.ps1','Test_Toolkit.ps1','Test_AuditSuite.ps1','Test_AuditCleaner.ps1','Test_AuditDnsPrivacy.ps1','Test_AuditRepairGaming.ps1','Test_AuditLaunchers.ps1','Test_FinalAuditGaming.ps1','Test_FinalAuditFixer.ps1')) {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $test)
    if ($LASTEXITCODE -ne 0) { throw "$test failed with exit $LASTEXITCODE" }
}
