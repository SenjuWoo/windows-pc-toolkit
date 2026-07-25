#requires -version 5.1
<#[
Encrypted DNS Manager v2.1
Configures one coherent provider at a time. Every configured DNS IP is paired
with its official HTTPS DoH template, UDP fallback is disabled, and prior DNS
state is saved for exact rollback.
]#>
param(
    [ValidateSet('Menu','Quad9','Mullvad','MullvadAdBlock','MullvadBase','MullvadExtended','MullvadFamily','MullvadAll','Verify','Restore','DHCP')]
    [string]$Action='Menu'
)

$ErrorActionPreference='Stop'
$Version='2.1'
$StateRoot=Join-Path $env:ProgramData 'WindowsPCToolkit\EncryptedDNS'
$SnapshotRoot=Join-Path $StateRoot 'Snapshots'

$Providers=[ordered]@{
    Quad9=[pscustomobject]@{Name='Quad9 Secure'; V4=@('9.9.9.9','149.112.112.112'); V6=@('2620:fe::fe','2620:fe::fe:9'); Template='https://dns.quad9.net/dns-query'; LiveTest='Quad9'}
    Mullvad=[pscustomobject]@{Name='Mullvad DNS'; V4=@('194.242.2.2'); V6=@('2a07:e340::2'); Template='https://dns.mullvad.net/dns-query'; LiveTest='Config'}
    MullvadAdBlock=[pscustomobject]@{Name='Mullvad AdBlock'; V4=@('194.242.2.3'); V6=@('2a07:e340::3'); Template='https://adblock.dns.mullvad.net/dns-query'; LiveTest='Config'}
    MullvadBase=[pscustomobject]@{Name='Mullvad Base'; V4=@('194.242.2.4'); V6=@('2a07:e340::4'); Template='https://base.dns.mullvad.net/dns-query'; LiveTest='Config'}
    MullvadExtended=[pscustomobject]@{Name='Mullvad Extended'; V4=@('194.242.2.5'); V6=@('2a07:e340::5'); Template='https://extended.dns.mullvad.net/dns-query'; LiveTest='Config'}
    MullvadFamily=[pscustomobject]@{Name='Mullvad Family'; V4=@('194.242.2.6'); V6=@('2a07:e340::6'); Template='https://family.dns.mullvad.net/dns-query'; LiveTest='Config'}
    MullvadAll=[pscustomobject]@{Name='Mullvad All'; V4=@('194.242.2.9'); V6=@('2a07:e340::9'); Template='https://all.dns.mullvad.net/dns-query'; LiveTest='Config'}
}

function Write-Status {
    param([ValidateSet('OK','INFO','WARN','FAIL')][string]$Kind,[string]$Message)
    $color=switch($Kind){'OK'{'Green'}'INFO'{'Cyan'}'WARN'{'Yellow'}default{'Red'}}
    $tag=switch($Kind){'OK'{'[OK]'}'INFO'{'[i]'}'WARN'{'[!!]'}default{'[X]'}}
    Write-Host ("  {0} {1}" -f $tag,$Message) -ForegroundColor $color
}
function Test-Admin {
    $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Assert-Admin { if(-not (Test-Admin)){throw 'Run this tool as Administrator.'} }
function Initialize-State { foreach($p in @($StateRoot,$SnapshotRoot)){if(-not(Test-Path -LiteralPath $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null}} }
function Get-TargetServers { @($Providers.Values | ForEach-Object { @($_.V4)+@($_.V6) } | ForEach-Object { $_ } | Select-Object -Unique) }
function Get-Adapters {
    $items=@(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
    if(-not $items){$items=@(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq 'Up' -and $_.Name -notmatch 'Loopback'})}
    return $items
}
function Test-AdapterIPv6 {
    param([int]$InterfaceIndex)
    $ips=@(Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -notlike 'fe80:*' -and $_.AddressState -in @('Preferred','Deprecated')})
    return ($ips.Count -gt 0)
}
function Get-StaticDnsServers {
    # Get-DnsClientServerAddress shows effective servers, including values
    # inherited from DHCP. The NameServer registry values identify whether
    # Windows was explicitly configured with static DNS before this tool ran.
    param([Parameter(Mandatory)]$Adapter)
    $guid=$Adapter.InterfaceGuid.ToString().Trim('{}')
    $paths=@{
        IPv4="HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{$guid}"
        IPv6="HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\{$guid}"
    }
    $result=[ordered]@{IPv4=@();IPv6=@()}
    foreach($family in @('IPv4','IPv6')){
        $raw=''
        try{$raw=[string](Get-ItemPropertyValue -LiteralPath $paths[$family] -Name 'NameServer' -ErrorAction Stop)}catch{}
        if(-not [string]::IsNullOrWhiteSpace($raw)){
            $result[$family]=@($raw -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }
    return [pscustomobject]$result
}
function Get-DohStateForServer {
    param([string]$Server)
    if(Get-Command Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue){
        try {
            $x=Get-DnsClientDohServerAddress -ServerAddress $Server -ErrorAction Stop
            if($x){return [pscustomobject]@{ServerAddress=$x.ServerAddress;DohTemplate=$x.DohTemplate;AllowFallbackToUdp=[bool]$x.AllowFallbackToUdp;AutoUpgrade=[bool]$x.AutoUpgrade}}
        }catch{}
    }
    try {
        $raw=@(& "$env:SystemRoot\System32\netsh.exe" dnsclient show encryption server=$Server 2>$null)
        if($LASTEXITCODE -ne 0 -or -not $raw){return $null}
        $text=$raw -join "`n"
        $template=[regex]::Match($text,'https://\S+').Value.TrimEnd('.',',',';')
        if(-not $template){return $null}
        $fallback=$null
        $upgrade=$null
        if($text -match '(?im)UDP\s+fallback[^\r\n]*:\s*(Yes|True|Enabled)'){ $fallback=$true }
        elseif($text -match '(?im)UDP\s+fallback[^\r\n]*:\s*(No|False|Disabled)'){ $fallback=$false }
        if($text -match '(?im)Auto\s*upgrade[^\r\n]*:\s*(Yes|True|Enabled)'){ $upgrade=$true }
        elseif($text -match '(?im)Auto\s*upgrade[^\r\n]*:\s*(No|False|Disabled)'){ $upgrade=$false }
        if($null -eq $fallback -or $null -eq $upgrade){return $null}
        return [pscustomobject]@{ServerAddress=$Server;DohTemplate=$template;AllowFallbackToUdp=[bool]$fallback;AutoUpgrade=[bool]$upgrade}
    }catch{}
    return $null
}
function New-DnsSnapshot {
    Initialize-State
    $adapters=foreach($a in Get-Adapters){
        $dns=Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue
        $effectiveV4=@(($dns|Where-Object AddressFamily -eq 2).ServerAddresses | Where-Object {$_})
        $effectiveV6=@(($dns|Where-Object AddressFamily -eq 23).ServerAddresses | Where-Object {$_})
        $static=Get-StaticDnsServers -Adapter $a
        [pscustomobject]@{
            InterfaceIndex=$a.ifIndex
            InterfaceGuid=$a.InterfaceGuid.ToString()
            Name=$a.Name
            Automatic=(@($static.IPv4).Count -eq 0 -and @($static.IPv6).Count -eq 0)
            StaticIPv4=@($static.IPv4)
            StaticIPv6=@($static.IPv6)
            EffectiveIPv4=$effectiveV4
            EffectiveIPv6=$effectiveV6
        }
    }
    $enc=foreach($s in Get-TargetServers){$state=Get-DohStateForServer $s;if($state){$state}}
    $currentProvider=$null
    $currentPath=Join-Path $StateRoot 'current_provider.json'
    if(Test-Path -LiteralPath $currentPath){try{$currentProvider=Get-Content -LiteralPath $currentPath -Raw|ConvertFrom-Json}catch{}}
    $obj=[pscustomobject]@{Schema=3;Created=(Get-Date).ToString('o');Computer=$env:COMPUTERNAME;Adapters=@($adapters);Encryption=@($enc);CurrentProvider=$currentProvider}
    $path=Join-Path $SnapshotRoot ("dns_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    $obj|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $path -Encoding ASCII
    Write-Status OK ("DNS snapshot saved: {0}" -f $path)
    return $path
}
function Get-LatestSnapshot {
    $pointer=Join-Path $StateRoot 'latest_snapshot.txt'
    if(Test-Path -LiteralPath $pointer){$p=(Get-Content -LiteralPath $pointer -Raw).Trim();if(Test-Path -LiteralPath $p){return $p}}
    $f=Get-ChildItem -LiteralPath $SnapshotRoot -Filter 'dns_*.json' -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if($f){return $f.FullName};return $null
}
function Remove-DohEntry {
    param([string]$Server)
    if(Get-Command Remove-DnsClientDohServerAddress -ErrorAction SilentlyContinue){Remove-DnsClientDohServerAddress -ServerAddress $Server -ErrorAction SilentlyContinue;return}
    & "$env:SystemRoot\System32\netsh.exe" dnsclient delete encryption server=$Server 2>$null|Out-Null
}
function Add-DohEntry {
    param([string]$Server,[string]$Template,[bool]$Fallback=$false,[bool]$Upgrade=$true)
    Remove-DohEntry $Server
    if(Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue){
        Add-DnsClientDohServerAddress -ServerAddress $Server -DohTemplate $Template -AllowFallbackToUdp $Fallback -AutoUpgrade $Upgrade -ErrorAction Stop
    }else{
        $fallbackText=if($Fallback){'yes'}else{'no'};$upgradeText=if($Upgrade){'yes'}else{'no'}
        $result=& "$env:SystemRoot\System32\netsh.exe" dnsclient add encryption server=$Server dohtemplate=$Template autoupgrade=$upgradeText udpfallback=$fallbackText 2>&1
        if($LASTEXITCODE -ne 0){throw "Could not register DoH for $Server. $($result -join ' ')"}
    }
}
function Test-WindowsDohSupport {
    $build=[int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    if($build -lt 22000){throw 'This encrypted DNS profile requires Windows 11. Windows 10 does not provide the same supported per-server DoH client configuration.'}
    if(-not(Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue) -and -not(Test-Path "$env:SystemRoot\System32\netsh.exe")){throw 'No supported Windows DoH configuration interface was found.'}
}
function Set-Provider {
    param([string]$Key)
    Assert-Admin;Test-WindowsDohSupport;Initialize-State
    $provider=$Providers[$Key];if(-not $provider){throw "Unknown provider: $Key"}
    $adapters=@(Get-Adapters);if(-not $adapters){throw 'No active network adapter was found.'}
    $snapshotPath=New-DnsSnapshot
    try{
        $servers=@($provider.V4)+@($provider.V6)
        foreach($unused in @(Get-TargetServers | Where-Object {$servers -notcontains $_})){Remove-DohEntry $unused}
        foreach($server in $servers){Add-DohEntry -Server $server -Template $provider.Template -Fallback $false -Upgrade $true;Write-Status OK ("Registered HTTPS template for {0}" -f $server)}
        foreach($a in $adapters){
            $addresses=@($provider.V4)
            if(Test-AdapterIPv6 $a.ifIndex){$addresses+=@($provider.V6)}
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $addresses -ErrorAction Stop
            Write-Status OK ("{0}: {1}" -f $a.Name,($addresses -join ', '))
        }
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Set-Content -LiteralPath (Join-Path $StateRoot 'current_provider.json') -Value ([pscustomobject]@{Key=$Key;Name=$provider.Name;Template=$provider.Template;Servers=$servers;Applied=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 4) -Encoding UTF8
        Write-Status OK ("Configured {0}. All selected IPs use {1}" -f $provider.Name,$provider.Template)
        if(-not(Test-Configuration -ProviderKey $Key)){throw 'Encrypted DNS verification failed.'}
    }catch{
        $applyError=$_.Exception.Message
        Write-Status WARN ("DNS change failed: {0}" -f $applyError)
        Write-Status INFO 'Rolling back the exact pre-change DNS state...'
        try{Restore-Snapshot -Path $snapshotPath}catch{Write-Status FAIL ("Automatic rollback also failed: {0}" -f $_.Exception.Message)}
        throw $applyError
    }
}
function Test-Configuration {
    param([string]$ProviderKey)
    Initialize-State
    if(-not $ProviderKey){
        $current=Join-Path $StateRoot 'current_provider.json'
        if(Test-Path -LiteralPath $current){$ProviderKey=(Get-Content -LiteralPath $current -Raw|ConvertFrom-Json).Key}
    }
    if(-not $ProviderKey -or -not $Providers[$ProviderKey]){Write-Status WARN 'No toolkit-managed provider is recorded. Showing Windows encryption entries only.';Show-EncryptionTable;return $false}
    $p=$Providers[$ProviderKey];$allGood=$true
    foreach($server in @($p.V4)+@($p.V6)){
        $state=Get-DohStateForServer $server
        if($state -and $state.DohTemplate -eq $p.Template -and -not $state.AllowFallbackToUdp -and $state.AutoUpgrade){Write-Status OK ("{0}: HTTPS template present, UDP fallback off" -f $server)}
        else{Write-Status FAIL ("{0}: encrypted template is missing or permits fallback" -f $server);$allGood=$false}
    }
    foreach($a in Get-Adapters){
        $actual=@((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue).ServerAddresses | Where-Object {$_})
        $expected=@($p.V4)
        if(Test-AdapterIPv6 $a.ifIndex){$expected+=@($p.V6)}
        Write-Host ("  {0} DNS: {1}" -f $a.Name,($actual -join ', '))
        $missing=@($expected | Where-Object {$actual -notcontains $_})
        $unexpected=@($actual | Where-Object {$expected -notcontains $_})
        if($missing.Count -gt 0 -or $unexpected.Count -gt 0){
            Write-Status FAIL ("{0}: adapter DNS does not exactly match {1}. Missing: {2}; unexpected: {3}" -f $a.Name,$p.Name,($missing -join ', '),($unexpected -join ', '))
            $allGood=$false
        }else{Write-Status OK ("{0}: adapter uses only the selected encrypted-DNS profile" -f $a.Name)}
    }
    try{Resolve-DnsName example.com -DnsOnly -ErrorAction Stop|Out-Null;Write-Status OK 'DNS resolution works.'}catch{Write-Status FAIL ("DNS resolution failed: {0}" -f $_.Exception.Message);$allGood=$false}
    if($p.LiveTest -eq 'Quad9'){
        try{
            $txt=@(Resolve-DnsName -Type TXT proto.on.quad9.net -DnsOnly -ErrorAction Stop|ForEach-Object {$_.Strings}|ForEach-Object {$_})
            $text=$txt -join ' '
            if($text -match '\bdoh\b'){Write-Status OK ("Quad9 live protocol test reports: {0}" -f $text)}
            else{Write-Status FAIL ("Quad9 live test did not report DoH: {0}" -f $text);$allGood=$false}
        }catch{Write-Status WARN ("Quad9 live protocol test unavailable: {0}" -f $_.Exception.Message)}
    }else{
        Write-Status INFO 'Mullvad does not expose the same Windows TXT transport test. The tool verified the Windows DoH template, disabled UDP fallback, and confirmed DNS resolution.'
    }
    if($allGood){Write-Status OK 'Encrypted DNS configuration checks passed.'}else{Write-Status WARN 'One or more checks failed. Do not assume DNS is encrypted until they pass.'}
    return [bool]$allGood
}
function Show-EncryptionTable {
    if(Get-Command Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue){Get-DnsClientDohServerAddress|Format-Table ServerAddress,DohTemplate,AllowFallbackToUdp,AutoUpgrade -AutoSize}
    else{& "$env:SystemRoot\System32\netsh.exe" dnsclient show encryption}
}
function Restore-Snapshot {
    param([string]$Path)
    Assert-Admin;Initialize-State
    $path=if($Path){$Path}else{Get-LatestSnapshot};if(-not $path -or -not(Test-Path -LiteralPath $path)){Write-Status WARN 'No DNS snapshot exists.';return}
    $snap=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    foreach($server in Get-TargetServers){Remove-DohEntry $server}
    foreach($entry in @($snap.Encryption)){Add-DohEntry -Server $entry.ServerAddress -Template $entry.DohTemplate -Fallback ([bool]$entry.AllowFallbackToUdp) -Upgrade ([bool]$entry.AutoUpgrade)}
    foreach($a in @($snap.Adapters)){
        $current=Get-NetAdapter -InterfaceIndex ([int]$a.InterfaceIndex) -ErrorAction SilentlyContinue
        if(-not $current){Write-Status WARN ("Adapter no longer exists: {0}" -f $a.Name);continue}
        # Schema 3 records automatic-vs-static state. Older snapshots are
        # still accepted, but cannot distinguish DHCP-provided DNS from static.
        if($a.PSObject.Properties.Name -contains 'Automatic'){
            if([bool]$a.Automatic){
                Set-DnsClientServerAddress -InterfaceIndex ([int]$a.InterfaceIndex) -ResetServerAddresses -ErrorAction Stop
                Write-Status OK ("{0}: restored automatic/DHCP DNS" -f $a.Name)
            }else{
                $addresses=@($a.StaticIPv4)+@($a.StaticIPv6) | Where-Object {$_}
                if($addresses.Count -eq 0){throw "Snapshot for $($a.Name) says static DNS but contains no static addresses."}
                Set-DnsClientServerAddress -InterfaceIndex ([int]$a.InterfaceIndex) -ServerAddresses $addresses -ErrorAction Stop
                Write-Status OK ("{0}: restored static DNS ({1})" -f $a.Name,($addresses -join ', '))
            }
        }else{
            $addresses=@($a.IPv4)+@($a.IPv6) | Where-Object {$_}
            if($addresses.Count -gt 0){Set-DnsClientServerAddress -InterfaceIndex ([int]$a.InterfaceIndex) -ServerAddresses $addresses -ErrorAction Stop}
            else{Set-DnsClientServerAddress -InterfaceIndex ([int]$a.InterfaceIndex) -ResetServerAddresses -ErrorAction Stop}
            Write-Status WARN ("{0}: restored from a legacy snapshot; DHCP/static mode was not recorded" -f $a.Name)
        }
    }
    $currentPath=Join-Path $StateRoot 'current_provider.json'
    if($snap.PSObject.Properties.Name -contains 'CurrentProvider' -and $null -ne $snap.CurrentProvider){$snap.CurrentProvider|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $currentPath -Encoding UTF8}
    else{Remove-Item -LiteralPath $currentPath -ErrorAction SilentlyContinue}
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-Status OK ("Exact DNS state restored from {0}" -f $path)
}
function Reset-Dhcp {
    Assert-Admin;Initialize-State
    $snapshotPath=New-DnsSnapshot
    try{
        foreach($a in Get-Adapters){Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction Stop;Write-Status OK ("{0}: DNS returned to DHCP/automatic" -f $a.Name)}
        foreach($server in Get-TargetServers){Remove-DohEntry $server}
        Remove-Item -LiteralPath (Join-Path $StateRoot 'current_provider.json') -ErrorAction SilentlyContinue
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Write-Status OK 'Automatic DNS restored and toolkit-created provider entries removed.'
    }catch{
        $resetError=$_.Exception.Message
        Write-Status WARN ("DHCP reset failed: {0}" -f $resetError)
        Write-Status INFO 'Rolling back the exact pre-reset DNS state...'
        try{Restore-Snapshot -Path $snapshotPath}catch{Write-Status FAIL ("Automatic rollback also failed: {0}" -f $_.Exception.Message)}
        throw $resetError
    }
}
function Show-Menu {
    Clear-Host
    Write-Host '  ================================================================' -ForegroundColor DarkCyan
    Write-Host ("  ENCRYPTED DNS MANAGER  v{0}" -f $Version) -ForegroundColor Yellow
    Write-Host '  Official HTTPS DoH templates, no plaintext fallback, exact undo' -ForegroundColor Gray
    Write-Host '  ================================================================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  [1] Quad9 Secure           Malware blocking, no ad blocking'
    Write-Host '  [2] Mullvad DNS            No filtering'
    Write-Host '  [3] Mullvad AdBlock        Ads and trackers'
    Write-Host '  [4] Mullvad Base           Ads, trackers, malware'
    Write-Host '  [5] Mullvad Extended       Base plus social tracking'
    Write-Host '  [6] Mullvad Family         Base plus adult and gambling'
    Write-Host '  [7] Mullvad All            Maximum published filtering'
    Write-Host '  [V] Verify current DoH configuration'
    Write-Host '  [R] Restore exact previous DNS state'
    Write-Host '  [D] Return active adapters to DHCP DNS'
    Write-Host '  [0] Exit'
    Write-Host ''
}

if($Action -ne 'Menu'){
    switch($Action){
        'Quad9'{Set-Provider Quad9}'Mullvad'{Set-Provider Mullvad}'MullvadAdBlock'{Set-Provider MullvadAdBlock}
        'MullvadBase'{Set-Provider MullvadBase}'MullvadExtended'{Set-Provider MullvadExtended}'MullvadFamily'{Set-Provider MullvadFamily}'MullvadAll'{Set-Provider MullvadAll}
        'Verify'{Test-Configuration|Out-Null}'Restore'{Restore-Snapshot}'DHCP'{Reset-Dhcp}
    }
    exit
}
while($true){
    Show-Menu;$c=(Read-Host '  Select').Trim().ToUpperInvariant()
    try{switch($c){'1'{Set-Provider Quad9}'2'{Set-Provider Mullvad}'3'{Set-Provider MullvadAdBlock}'4'{Set-Provider MullvadBase}'5'{Set-Provider MullvadExtended}'6'{Set-Provider MullvadFamily}'7'{Set-Provider MullvadAll}'V'{Test-Configuration|Out-Null}'R'{Restore-Snapshot}'D'{Reset-Dhcp}'0'{break}default{Write-Status WARN 'Invalid selection.'}}}catch{Write-Status FAIL $_.Exception.Message}
    if($c -eq '0'){break};Write-Host '';Read-Host '  Press Enter to continue'|Out-Null
}
