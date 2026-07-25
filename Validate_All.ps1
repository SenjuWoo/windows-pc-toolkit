#requires -version 5.1
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$failed=$false
$gamingRoot=if(Test-Path -LiteralPath (Join-Path $root 'Pc Gaming Optimizer')){Join-Path $root 'Pc Gaming Optimizer'}else{Join-Path $root 'pc-gaming-optimizer'}
$dnsManager=if(Test-Path -LiteralPath (Join-Path $root 'Pc Privacy Guard\Optional DNS\DNS_Manager.ps1')){Join-Path $root 'Pc Privacy Guard\Optional DNS\DNS_Manager.ps1'}else{Join-Path $root 'dns-encrypted-doh\DNS_Manager.ps1'}
$privacyPath=if(Test-Path -LiteralPath (Join-Path $root 'Pc Privacy Guard\PC_Privacy.ps1')){Join-Path $root 'Pc Privacy Guard\PC_Privacy.ps1'}else{Join-Path $root 'pc-privacy-guard\PC_Privacy.ps1'}
$gamingCore=Join-Path $gamingRoot 'Modules\Optimizer.Core.psm1'
if(-not(Test-Path -LiteralPath $gamingRoot)){$failed=$true;Write-Host '[FAIL] Gaming Optimizer folder not found.' -ForegroundColor Red}
if(-not(Test-Path -LiteralPath $dnsManager)){$failed=$true;Write-Host '[FAIL] DNS Manager script not found.' -ForegroundColor Red}
if(-not(Test-Path -LiteralPath $privacyPath)){$failed=$true;Write-Host '[FAIL] Privacy Guard script not found.' -ForegroundColor Red}
if(-not(Test-Path -LiteralPath $gamingCore)){$failed=$true;Write-Host '[FAIL] Gaming Optimizer core module not found.' -ForegroundColor Red}
# Exclude only a nested staging folder under $root (not when the repo itself lives under a path named _github_publish).
function Test-IsNestedGithubPublish([string]$fullPath,[string]$rootPath){
    if($fullPath.Length -le $rootPath.Length){ return $false }
    $rel = $fullPath.Substring($rootPath.Length).TrimStart('\','/')
    return ($rel -match '(?i)(^|[/\\])_github_publish([/\\]|$)')
}
$files=@(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $_.Extension -in @('.ps1','.psm1') -and -not (Test-IsNestedGithubPublish $_.FullName $root)
})
Write-Host "Parsing $($files.Count) PowerShell files..." -ForegroundColor Cyan
foreach($file in $files){
    $tokens=$null;$errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count){$failed=$true;Write-Host "[FAIL] $($file.FullName)" -ForegroundColor Red;$errors|ForEach-Object{Write-Host ("       {0} at line {1}" -f $_.Message,$_.Extent.StartLineNumber) -ForegroundColor Red}}
    else{Write-Host "[ OK ] $($file.FullName.Substring($root.Length+1))" -ForegroundColor Green}
}

Write-Host "`nChecking launchers..." -ForegroundColor Cyan
foreach($bat in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.bat' -File | Where-Object { -not (Test-IsNestedGithubPublish $_.FullName $root) }){
    $text=Get-Content -LiteralPath $bat.FullName -Raw
    if($text -notmatch [regex]::Escape('%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe')){$failed=$true;Write-Host "[FAIL] Launcher does not use absolute PowerShell path: $($bat.FullName)" -ForegroundColor Red}
}

Write-Host "`nChecking encrypted DNS templates..." -ForegroundColor Cyan
$dns=Get-Content -LiteralPath $dnsManager -Raw
if($dns -match "Template='http://"){$failed=$true;Write-Host '[FAIL] Plain HTTP DoH template found.' -ForegroundColor Red}
foreach($required in @('https://dns.quad9.net/dns-query','https://dns.mullvad.net/dns-query','https://adblock.dns.mullvad.net/dns-query')){if($dns -notmatch [regex]::Escape($required)){$failed=$true;Write-Host "[FAIL] Missing DoH template: $required" -ForegroundColor Red}}
foreach($required in @('9.9.9.9','149.112.112.112','2620:fe::fe','2620:fe::fe:9')){if($dns -notmatch [regex]::Escape($required)){$failed=$true;Write-Host "[FAIL] Missing Quad9 secure-profile address: $required" -ForegroundColor Red}}
if($dns -match [regex]::Escape("'2620:fe::9'")){$failed=$true;Write-Host '[FAIL] Quad9 address 2620:fe::9 belongs to a different service family.' -ForegroundColor Red}
if($dns -notmatch 'Add-DohEntry[^\r\n]+-Fallback\s+\$false[^\r\n]+-Upgrade\s+\$true'){$failed=$true;Write-Host '[FAIL] DNS profile application does not force DoH with UDP fallback disabled.' -ForegroundColor Red}
foreach($required in @('Get-StaticDnsServers','Automatic=','StaticIPv4','StaticIPv6','Schema=3','-ResetServerAddresses')){if($dns -notmatch [regex]::Escape($required)){$failed=$true;Write-Host "[FAIL] Missing DNS mode-aware rollback marker: $required" -ForegroundColor Red}}

Write-Host "`nChecking that unsafe writes were not reintroduced..." -ForegroundColor Cyan
$gamingFiles=@(Get-ChildItem -LiteralPath $gamingRoot -Recurse -Include '*.ps1','*.psm1' -File)
$gamingText=($gamingFiles|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw}) -join "`n"
$badPatterns=@(
    'Set-ItemProperty[^\r\n]*(NetworkThrottlingIndex|SystemResponsiveness|TcpAckFrequency|TCPNoDelay|NtfsMemoryUsage|PowerMizer)',
    'New-ItemProperty[^\r\n]*(NetworkThrottlingIndex|SystemResponsiveness|TcpAckFrequency|TCPNoDelay|NtfsMemoryUsage|PowerMizer)',
    'Set-NetAdapterRsc[^\r\n]*(false|disabled)',
    'NtSetSystemInformation',
    'Set-Service[^\r\n]SysMain[^\r\n]Disabled'
)
foreach($pattern in $badPatterns){if($gamingText -match $pattern){$failed=$true;Write-Host "[FAIL] Unsafe optimization write matched: $pattern" -ForegroundColor Red}}
foreach($match in Select-String -Path $gamingFiles.FullName -Pattern 'bcdedit\.exe[^\r\n]*/set'){
    if($match.Line -notmatch '\$bcdState'){$failed=$true;Write-Host "[FAIL] Non-rollback BCD override: $($match.Path):$($match.LineNumber)" -ForegroundColor Red}
}



Write-Host "`nChecking Privacy Guard policy safety..." -ForegroundColor Cyan
$privacyText=Get-Content -LiteralPath $privacyPath -Raw
foreach($forbidden in @('BingSearchEnabled','CortanaConsent')){
    if($privacyText -match [regex]::Escape($forbidden)){$failed=$true;Write-Host "[FAIL] Legacy Windows Search toggle reintroduced: $forbidden" -ForegroundColor Red}
}
foreach($required in @('Apply-DiagnosticPromptPrivacy','AllowCloudSearch','EnableDynamicContentInWSB')){
    if($privacyText -notmatch [regex]::Escape($required)){$failed=$true;Write-Host "[FAIL] Missing current Privacy Guard marker: $required" -ForegroundColor Red}
}

Write-Host "`nChecking cross-tool path resolver..." -ForegroundColor Cyan
if(Test-Path -LiteralPath $gamingCore){
    $gamingCoreText=Get-Content -LiteralPath $gamingCore -Raw
    if($gamingCoreText -notmatch 'function\s+Resolve-SuiteToolPath'){$failed=$true;Write-Host '[FAIL] Gaming Optimizer core is missing Resolve-SuiteToolPath.' -ForegroundColor Red}
}

Write-Host "`nChecking PC Fixer safety regressions..." -ForegroundColor Cyan
$fixerPath=if(Test-Path -LiteralPath (Join-Path $root 'Pc Corruption Fixer\PC_Fixer.ps1')){Join-Path $root 'Pc Corruption Fixer\PC_Fixer.ps1'}else{Join-Path $root 'pc-corruption-fixer\PC_Fixer.ps1'}
$fixerText=Get-Content -LiteralPath $fixerPath -Raw
foreach($forbidden in @('Remove-AppxPackage','CopilotSvc','BingSearchEnabled','TurnOffWindowsAI')){
    if($fixerText -match [regex]::Escape($forbidden)){$failed=$true;Write-Host "[FAIL] Destructive or unsupported AI tweak reintroduced: $forbidden" -ForegroundColor Red}
}
foreach($required in @('AIFeatureSnapshots','DisableAIDataAnalysis','GenAILocalFoundationalModelSettings','Restore-AiFeatureSnapshot','Get-StaticNetworkDnsServers','Automatic =','StaticIPv4','StaticIPv6','Network reset aborted because DNS/DoH state could not be backed up','Also reset the TCP/IP stack?')){
    if($fixerText -notmatch [regex]::Escape($required)){$failed=$true;Write-Host "[FAIL] Missing reversible AI privacy marker: $required" -ForegroundColor Red}
}

Write-Host "`nChecking DNS launcher semantics..." -ForegroundColor Cyan
$dnsFolder=Split-Path -Parent $dnsManager
$dhcpLauncher=Join-Path $dnsFolder 'DNS_Revert_DHCP.ps1'
$restoreLauncher=Join-Path $dnsFolder 'DNS_Restore_Previous.ps1'
if(-not(Test-Path -LiteralPath $dhcpLauncher) -or (Get-Content -LiteralPath $dhcpLauncher -Raw) -notmatch '-Action\s+DHCP'){$failed=$true;Write-Host '[FAIL] DHCP launcher does not invoke the DHCP action.' -ForegroundColor Red}
if(-not(Test-Path -LiteralPath $restoreLauncher) -or (Get-Content -LiteralPath $restoreLauncher -Raw) -notmatch '-Action\s+Restore'){$failed=$true;Write-Host '[FAIL] Snapshot restore launcher is missing or incorrect.' -ForegroundColor Red}
if($dns -notmatch 'function\s+Reset-Dhcp[\s\S]{0,1600}Restore-Snapshot\s+-Path\s+\$snapshotPath'){$failed=$true;Write-Host '[FAIL] DHCP reset is not transactionally rolled back.' -ForegroundColor Red}

if($failed){Write-Host "`nVALIDATION FAILED" -ForegroundColor Red;exit 1}
Write-Host "`nALL VALIDATION CHECKS PASSED" -ForegroundColor Green
