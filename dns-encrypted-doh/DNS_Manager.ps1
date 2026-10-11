#requires -version 5.1
<#[
Encrypted DNS Manager v2.2.2
Configures one coherent provider at a time. Every configured DNS IP is paired
with its official HTTPS DoH template, UDP fallback is disabled, and prior DNS
state is saved for exact rollback.
]#>
param(
    [ValidateSet('Menu','Library','Quad9','AdGuard','Mullvad','MullvadAdBlock','MullvadBase','MullvadExtended','MullvadFamily','MullvadAll','Verify','Restore','DHCP')]
    [string]$Action='Menu',
    [int[]]$InterfaceIndex,
    [string]$SnapshotPath,
    [switch]$DebugLog
)

$ErrorActionPreference='Stop'
$networkModule=@((Join-Path $PSScriptRoot '..\Modules\Network.State.psm1'),(Join-Path $PSScriptRoot '..\..\Modules\Network.State.psm1')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $networkModule) { throw 'The shared network module is missing. Extract the complete toolkit.' }
Import-Module $networkModule -Force -DisableNameChecking
$Version='2.2.2'
$StateRoot=Join-Path $env:ProgramData 'WindowsPCToolkit\EncryptedDNS'
$SnapshotRoot=Join-Path $StateRoot 'Snapshots'
$DnsDebug=($DebugLog -or $env:WINDOWS_PC_TOOLKIT_DEBUG -eq '1')
$DnsLog=Join-Path $env:LOCALAPPDATA 'WindowsPCToolkit\Logs\DNS.log'
function Write-DnsDiagnostic {
    param([string]$Kind,[string]$Message)
    if (-not $DnsDebug -and $Kind -notin @('FAIL','WARN')) { return }
    try {
        if ($Message.Length -gt 4096) { $Message=$Message.Substring(0,4096) }
        [IO.Directory]::CreateDirectory((Split-Path $DnsLog -Parent))|Out-Null
        [pscustomobject]@{Time=(Get-Date).ToString('o');Version=$Version;Kind=$Kind;Message=$Message} | ConvertTo-Json -Compress | Add-Content -LiteralPath $DnsLog -Encoding UTF8
    } catch { Write-Warning "DNS diagnostic log could not be written: $($_.Exception.Message)" }
}
Write-DnsDiagnostic 'DEBUG' "Startup: action=$Action; interfaces=$($InterfaceIndex -join ','); snapshot=$SnapshotPath"

$Providers=[ordered]@{
    Quad9=[pscustomobject]@{Name='Quad9 Secure'; V4=@('9.9.9.9','149.112.112.112'); V6=@('2620:fe::fe','2620:fe::9'); Template='https://dns.quad9.net/dns-query'; LiveTest='Quad9'}
    AdGuard=[pscustomobject]@{Name='AdGuard DNS'; V4=@('94.140.14.14','94.140.15.15'); V6=@('2a10:50c0::ad1:ff','2a10:50c0::ad2:ff'); Template='https://dns.adguard-dns.com/dns-query'; LiveTest='Config'}
}

function Write-Status {
    param([ValidateSet('OK','INFO','WARN','FAIL')][string]$Kind,[string]$Message)
    $color=switch($Kind){'OK'{'Green'}'INFO'{'Cyan'}'WARN'{'Yellow'}default{'Red'}}
    $tag=switch($Kind){'OK'{'[OK]'}'INFO'{'[i]'}'WARN'{'[!!]'}default{'[X]'}}
    Write-Host ("  {0} {1}" -f $tag,$Message) -ForegroundColor $color
    Write-DnsDiagnostic $Kind $Message
}
function Test-Admin {
    $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Assert-Admin { if(-not (Test-Admin)){throw 'Run this tool as Administrator.'} }
function Assert-DnsStatePath {
    param([string]$Path,[switch]$Snapshot)
    $resolved=[IO.Path]::GetFullPath($Path)
    if ($Snapshot -and -not $resolved.StartsWith(([IO.Path]::GetFullPath($SnapshotRoot).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'DNS snapshot is outside its snapshot folder.' }
    $cursor=$resolved
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor -ErrorAction Stop) {
            if ((Get-Item -LiteralPath $cursor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked DNS state path is unsupported: $cursor" }
        }
        $parent=[IO.Path]::GetDirectoryName($cursor); if ($parent -eq $cursor) { break }; $cursor=$parent
    }
}
function Initialize-State { foreach($p in @($StateRoot,$SnapshotRoot)){Assert-DnsStatePath $p;if(-not(Test-Path -LiteralPath $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null}} }
function Get-TargetServers { @($Providers.Values | ForEach-Object { @($_.V4)+@($_.V6) } | ForEach-Object { $_ } | Select-Object -Unique) }
function Get-Adapters {
    $items=@(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up')
    if ($InterfaceIndex) {
        $items=@($items | Where-Object { $InterfaceIndex -contains $_.ifIndex })
        if ($items.Count -ne @($InterfaceIndex | Select-Object -Unique).Count) { throw 'Select an active physical adapter. VPN and virtual adapters are preserved.' }
    } else {
        $routes=@(Get-NetRoute -ErrorAction Stop | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0','::/0') })
        $items=@($items | Where-Object { $routes.InterfaceIndex -contains $_.ifIndex })
    }
    if (-not $items) { throw 'No active physical adapter with a default route was found. Specify -InterfaceIndex for a physical adapter.' }
    return $items
}
function Test-AdapterIPv6 {
    param([int]$InterfaceIndex)
    $ips=@(Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -notlike 'fe80:*' -and $_.AddressState -in @('Preferred','Deprecated')})
    if (-not $ips.Count) { return $false }
    $routes=@(Get-NetRoute -InterfaceIndex $InterfaceIndex -AddressFamily IPv6 -ErrorAction Stop | Where-Object DestinationPrefix -eq '::/0')
    return ($ips.Count -gt 0 -and $routes.Count -gt 0)
}
function Get-StaticDnsServers {
    param([Parameter(Mandatory)]$Adapter)
    Get-AdapterStaticDnsServers -Adapter $Adapter
}
function Get-DohStateForServer {
    param([string]$Server)
    $x=Get-DnsClientDohServerAddress -ErrorAction Stop | Where-Object ServerAddress -eq $Server | Select-Object -First 1
    if($x){return [pscustomobject]@{ServerAddress=$x.ServerAddress;DohTemplate=$x.DohTemplate;AllowFallbackToUdp=[bool]$x.AllowFallbackToUdp;AutoUpgrade=[bool]$x.AutoUpgrade}}
    return $null
}
function New-DnsSnapshot {
    param([string[]]$TouchedServers=(Get-TargetServers))
    Initialize-State
    $adapters=foreach($a in Get-Adapters){
        $dns=Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ErrorAction Stop
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
    $enc=foreach($s in $TouchedServers){$state=Get-DohStateForServer $s;if($state){$state}}
    $currentProvider=$null
    $currentPath=Join-Path $StateRoot 'current_provider.json'
    Assert-DnsStatePath $currentPath
    if(Test-Path -LiteralPath $currentPath){$currentProvider=Get-Content -LiteralPath $currentPath -Raw -Encoding UTF8|ConvertFrom-Json}
    $obj=[pscustomobject]@{Schema=4;Created=(Get-Date).ToString('o');Computer=$env:COMPUTERNAME;Adapters=@($adapters);Encryption=@($enc);TouchedServers=@($TouchedServers);CurrentProvider=$currentProvider}
    Assert-DnsSnapshot $obj
    $path=Join-Path $SnapshotRoot ("dns_{0}_{1}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'),[guid]::NewGuid().ToString('N'))
    Assert-DnsStatePath $path -Snapshot
    $obj|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
    $verified=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ((ConvertTo-Json -InputObject $verified -Depth 8 -Compress) -ne (ConvertTo-Json -InputObject $obj -Depth 8 -Compress)) { throw 'DNS backup verification failed; no DNS settings were changed.' }
    Assert-DnsStatePath (Join-Path $StateRoot 'latest_snapshot.txt')
    Set-Content -LiteralPath (Join-Path $StateRoot 'latest_snapshot.txt') -Value $path -Encoding UTF8
    Write-Status OK ("DNS snapshot saved: {0}" -f $path)
    return $path
}
function Get-LatestSnapshot {
    Assert-DnsStatePath $SnapshotRoot
    $pointer=Join-Path $StateRoot 'latest_snapshot.txt'
    Assert-DnsStatePath $pointer
    if(Test-Path -LiteralPath $pointer){$p=(Get-Content -LiteralPath $pointer -Raw).Trim();Assert-DnsStatePath $p -Snapshot;if(Test-Path -LiteralPath $p -PathType Leaf){return $p}}
    $f=Get-ChildItem -LiteralPath $SnapshotRoot -Filter 'dns_*.json' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if($f){Assert-DnsStatePath $f.FullName -Snapshot;return $f.FullName};return $null
}
function Remove-DohEntry {
    param([string]$Server)
    if (Get-DohStateForServer $Server) { Remove-DnsClientDohServerAddress -ServerAddress $Server -ErrorAction Stop }
    if (Get-DohStateForServer $Server) { throw "DoH removal read-back failed for $Server." }
}
function Add-DohEntry {
    param([string]$Server,[string]$Template,[bool]$Fallback=$false,[bool]$Upgrade=$true)
    if (Get-DohStateForServer $Server) { Set-DnsClientDohServerAddress -ServerAddress $Server -DohTemplate $Template -AllowFallbackToUdp $Fallback -AutoUpgrade $Upgrade -ErrorAction Stop }
    else { Add-DnsClientDohServerAddress -ServerAddress $Server -DohTemplate $Template -AllowFallbackToUdp $Fallback -AutoUpgrade $Upgrade -ErrorAction Stop }
    $actual=Get-DohStateForServer $Server
    if (-not $actual -or $actual.DohTemplate -ne $Template -or $actual.AllowFallbackToUdp -ne $Fallback -or $actual.AutoUpgrade -ne $Upgrade) { throw "DoH write read-back failed for $Server." }
}
function Test-WindowsDohSupport {
    $build=[int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    if($build -lt 22000){throw 'This encrypted DNS profile requires Windows 11. Windows 10 does not provide the same supported per-server DoH client configuration.'}
    foreach ($command in @('Get-DnsClientDohServerAddress','Add-DnsClientDohServerAddress','Set-DnsClientDohServerAddress','Remove-DnsClientDohServerAddress')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "The supported Windows DoH interface is unavailable: $command. No DNS settings were changed." }
    }
}
function Set-Provider {
    param([string]$Key)
    if ($Key -like 'Mullvad*') { throw 'Mullvad public DNS retires November 2, 2026. New applies are removed; choose Quad9 or AdGuard. Previous backups remain restorable.' }
    Assert-Admin;Test-WindowsDohSupport;Initialize-State
    $provider=$Providers[$Key];if(-not $provider){throw "Unknown or retired provider: $Key. Choose Quad9 or AdGuard."}
    $adapters=@(Get-Adapters);if(-not $adapters){throw 'No active network adapter was found.'}
    $servers=@($provider.V4)+@($provider.V6)
    $snapshotPath=New-DnsSnapshot -TouchedServers $servers
    try{
        foreach($server in $servers){Add-DohEntry -Server $server -Template $provider.Template -Fallback $false -Upgrade $true;Write-Status OK ("Registered HTTPS template for {0}" -f $server)}
        foreach($a in $adapters){
            $v6=@(); if(Test-AdapterIPv6 $a.ifIndex){$v6=@($provider.V6)}
            $addresses=@($provider.V4)+$v6
            Set-AdapterDnsFamilies -Index $a.ifIndex -IPv4 $provider.V4 -IPv6 $v6
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
        $actual=@((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ErrorAction Stop).ServerAddresses | Where-Object {$_})
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
        }catch{Write-Status FAIL ("Quad9 live protocol test unavailable: {0}" -f $_.Exception.Message);$allGood=$false}
    }else{
        Write-Status INFO 'This provider does not expose the Quad9 TXT transport test. Windows DoH configuration and DNS resolution are checked; a live transport attestation is not available.'
    }
    if($allGood){Write-Status OK 'Encrypted DNS configuration checks passed.'}else{Write-Status WARN 'One or more checks failed. Do not assume DNS is encrypted until they pass.'}
    return [bool]$allGood
}
function Show-EncryptionTable {
    Get-DnsClientDohServerAddress -ErrorAction Stop|Format-Table ServerAddress,DohTemplate,AllowFallbackToUdp,AutoUpgrade -AutoSize
}
function Assert-DnsServerList {
    param($Servers,[int]$Family=0)
    if ($Servers -isnot [Array]) { throw 'DNS backup contains an invalid server list; no DNS settings were changed.' }
    $seen=@{}
    foreach ($server in $Servers) {
        $ip=$null
        if ($server -isnot [string] -or -not [Net.IPAddress]::TryParse($server,[ref]$ip) -or ($Family -and [int]$ip.AddressFamily -ne $Family)) { throw 'DNS backup contains an invalid address family or IP; no DNS settings were changed.' }
        $key=$ip.ToString()
        if ($seen.ContainsKey($key)) { throw 'DNS backup contains duplicate server addresses; no DNS settings were changed.' }; $seen[$key]=$true
    }
}
function Assert-DnsTemplate {
    param($Template)
    $uri=$null
    if ($Template -isnot [string] -or -not [Uri]::TryCreate($Template,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or -not $uri.Host -or $uri.UserInfo -or $uri.Fragment) { throw 'DNS backup contains an invalid HTTPS template; no DNS settings were changed.' }
}
function Get-SnapshotTouchedServers {
    param($Snapshot)
    if ($Snapshot.PSObject.Properties.Name -contains 'TouchedServers') { return ,@($Snapshot.TouchedServers) }
    # Older backups do not identify absent entries that an apply created. Do not
    # infer a destructive global cleanup from today's different provider table.
    return ,@($Snapshot.Encryption | ForEach-Object ServerAddress)
}
function Assert-DnsSnapshot {
    param($Snapshot)
    if ($null -eq $Snapshot -or $Snapshot.Schema -isnot [int] -or $Snapshot.Schema -notin @(2,3,4) -or $Snapshot.Adapters -isnot [Array] -or -not $Snapshot.Adapters.Count -or $Snapshot.Encryption -isnot [Array]) { throw 'Unsupported or malformed DNS backup; no DNS settings were changed.' }
    if (($Snapshot.PSObject.Properties.Name -contains 'Computer' -and ($Snapshot.Computer -isnot [string] -or -not $Snapshot.Computer)) -or ($Snapshot.PSObject.Properties.Name -contains 'TouchedServers' -and $Snapshot.TouchedServers -isnot [Array])) { throw 'DNS backup contains invalid identity or touched-server state; no DNS settings were changed.' }
    if ($Snapshot.Schema -eq 4 -and ($Snapshot.PSObject.Properties.Name -notcontains 'Computer' -or $Snapshot.Computer -isnot [string] -or -not $Snapshot.Computer -or $Snapshot.PSObject.Properties.Name -notcontains 'TouchedServers' -or $Snapshot.TouchedServers -isnot [Array])) { throw 'DNS backup is missing required identity or touched-server state; no DNS settings were changed.' }
    $seen=@{}
    foreach ($a in $Snapshot.Adapters) {
        $guid=[guid]::Empty
        if ($null -eq $a -or $a.InterfaceGuid -isnot [string] -or -not [guid]::TryParse($a.InterfaceGuid,[ref]$guid) -or $guid -eq [guid]::Empty -or $seen.ContainsKey($guid.ToString())) { throw 'DNS backup has invalid or duplicate adapter identities; no DNS settings were changed.' }; $seen[$guid.ToString()]=$true
        if ($Snapshot.Schema -ge 3 -or $a.PSObject.Properties.Name -contains 'Automatic') {
            if ($a.PSObject.Properties.Name -notcontains 'Automatic' -or $a.Automatic -isnot [bool] -or $a.PSObject.Properties.Name -notcontains 'StaticIPv4' -or $a.PSObject.Properties.Name -notcontains 'StaticIPv6') { throw 'DNS backup has invalid automatic/static state; no DNS settings were changed.' }
            Assert-DnsServerList $a.StaticIPv4 2; Assert-DnsServerList $a.StaticIPv6 23
            $count=$a.StaticIPv4.Count+$a.StaticIPv6.Count
            if (($a.Automatic -and $count) -or (-not $a.Automatic -and -not $count)) { throw "DNS backup has inconsistent address modes for $($a.Name); no DNS settings were changed." }
        } else { Assert-DnsServerList $a.IPv4 2; Assert-DnsServerList $a.IPv6 23 }
    }
    $touched=Get-SnapshotTouchedServers $Snapshot
    Assert-DnsServerList $touched
    $scope=@{};foreach ($server in $touched) { $scope[([Net.IPAddress]::Parse($server)).ToString()]=$true }
    $seen=@{}
    foreach ($entry in $Snapshot.Encryption) {
        if ($null -eq $entry -or $entry.ServerAddress -isnot [string] -or $entry.AllowFallbackToUdp -isnot [bool] -or $entry.AutoUpgrade -isnot [bool]) { throw 'DNS backup contains invalid encryption address or flags; no DNS settings were changed.' }
        Assert-DnsServerList @($entry.ServerAddress); Assert-DnsTemplate $entry.DohTemplate
        $key=([Net.IPAddress]::Parse($entry.ServerAddress)).ToString()
        if (-not $scope.ContainsKey($key) -or $seen.ContainsKey($key)) { throw 'DNS encryption entry is duplicated or outside its saved scope; no DNS settings were changed.' };$seen[$key]=$true
    }
    if ($Snapshot.PSObject.Properties.Name -contains 'CurrentProvider' -and $null -ne $Snapshot.CurrentProvider) {
        $provider=$Snapshot.CurrentProvider
        if ($provider.Key -isnot [string] -or -not $provider.Key -or $provider.Name -isnot [string] -or $provider.Applied -isnot [string]) { throw 'DNS backup contains invalid provider metadata; no DNS settings were changed.' }
        Assert-DnsTemplate $provider.Template; Assert-DnsServerList $provider.Servers
    }
}
function Restore-Snapshot {
    param([string]$Path)
    Assert-Admin;Initialize-State
    $path=if($Path){$Path}else{Get-LatestSnapshot};if(-not $path -or -not(Test-Path -LiteralPath $path)){throw 'No DNS snapshot exists.'}
    Assert-DnsStatePath $path -Snapshot
    $snap=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    # Earlier captures retained native REG_SZ terminator padding in addresses.
    foreach($adapter in @($snap.Adapters)) {
        foreach($field in @('StaticIPv4','StaticIPv6','IPv4','IPv6')) {
            if($adapter.PSObject.Properties.Name -contains $field -and $adapter.$field -is [Array]) {
                $adapter.$field=@($adapter.$field | ForEach-Object {if($_ -is [string]){$_.TrimEnd([char]0)}else{$_}})
            }
        }
    }
    Assert-DnsSnapshot $snap
    Assert-DnsStatePath (Join-Path $StateRoot 'current_provider.json')
    if ($snap.PSObject.Properties.Name -contains 'Computer' -and $snap.Computer -ne $env:COMPUTERNAME) { throw 'This DNS backup belongs to another computer.' }
    if (-not @($snap.Adapters).Count) { throw 'DNS backup contains no adapters; no DNS settings were changed.' }
    $availableAdapters=@(Get-NetAdapter -ErrorAction Stop)
    foreach ($a in @($snap.Adapters)) {
        if ($a.PSObject.Properties.Name -notcontains 'InterfaceGuid') { throw 'This legacy backup has no stable adapter identity; no DNS settings were changed.' }
        $current=@($availableAdapters | Where-Object { $_.InterfaceGuid.ToString().Trim('{}') -eq $a.InterfaceGuid.ToString().Trim('{}') })
        if ($current.Count -ne 1) { throw "Original adapter no longer exists: $($a.Name). No DNS settings were changed." }
        $families=@(Get-DnsClientServerAddress -InterfaceIndex $current[0].ifIndex -ErrorAction Stop)
        if (-not $families.Count) { throw 'Original adapter exposes no DNS address families; no DNS settings were changed.' }
        foreach ($family in @(@{Id=2;Field='IPv4'},@{Id=23;Field='IPv6'})) {
            $field=if ($a.PSObject.Properties.Name -contains 'Automatic') { 'Static'+$family.Field } else { $family.Field }
            if (@($a.$field).Count -and -not @($families | Where-Object { [int]$_.AddressFamily -eq $family.Id }).Count) { throw "Original adapter no longer exposes $($family.Field); no DNS settings were changed." }
        }
        if ($a.PSObject.Properties.Name -contains 'Automatic') {
            if ($a.Automatic -isnot [bool] -or $a.PSObject.Properties.Name -notcontains 'StaticIPv4' -or $a.PSObject.Properties.Name -notcontains 'StaticIPv6') { throw 'DNS backup has invalid automatic/static state; no DNS settings were changed.' }
            $addresses=@(@($a.StaticIPv4)+@($a.StaticIPv6) | Where-Object {$_})
            if (([bool]$a.Automatic -and $addresses.Count) -or (-not [bool]$a.Automatic -and -not $addresses.Count)) { throw "DNS backup has inconsistent address modes for $($a.Name); no DNS settings were changed." }
        }
    }
    $touched=Get-SnapshotTouchedServers $snap
    foreach($server in $touched | Where-Object { @($snap.Encryption | ForEach-Object ServerAddress) -notcontains $_ }){Remove-DohEntry $server}
    foreach($entry in @($snap.Encryption)){Add-DohEntry -Server $entry.ServerAddress -Template $entry.DohTemplate -Fallback ([bool]$entry.AllowFallbackToUdp) -Upgrade ([bool]$entry.AutoUpgrade)}
    foreach($a in @($snap.Adapters)){
        $current=Get-NetAdapter -ErrorAction Stop | Where-Object { $_.InterfaceGuid.ToString().Trim('{}') -eq $a.InterfaceGuid.ToString().Trim('{}') } | Select-Object -First 1
        if(-not $current){throw "Original adapter no longer exists: $($a.Name). No different adapter will be changed."}
        # Schema 3 records automatic-vs-static state. Older snapshots are
        # still accepted, but cannot distinguish DHCP-provided DNS from static.
        if($a.PSObject.Properties.Name -contains 'Automatic'){
            if([bool]$a.Automatic){
                Set-AdapterDnsFamilies -Index $current.ifIndex
                Write-Status OK ("{0}: restored automatic/DHCP DNS" -f $a.Name)
            }else{
                $addresses=@(@($a.StaticIPv4)+@($a.StaticIPv6) | Where-Object {$_})
                if($addresses.Count -eq 0){throw "Snapshot for $($a.Name) says static DNS but contains no static addresses."}
                Set-AdapterDnsFamilies -Index $current.ifIndex -IPv4 @($a.StaticIPv4) -IPv6 @($a.StaticIPv6)
                Write-Status OK ("{0}: restored static DNS ({1})" -f $a.Name,($addresses -join ', '))
            }
        }else{
            $addresses=@(@($a.IPv4)+@($a.IPv6) | Where-Object {$_})
            Set-AdapterDnsFamilies -Index $current.ifIndex -IPv4 @($a.IPv4) -IPv6 @($a.IPv6)
            Write-Status WARN ("{0}: restored from a legacy snapshot; DHCP/static mode was not recorded" -f $a.Name)
        }
    }
    $currentPath=Join-Path $StateRoot 'current_provider.json'
    Assert-DnsStatePath $currentPath
    if($snap.PSObject.Properties.Name -contains 'CurrentProvider' -and $null -ne $snap.CurrentProvider){$snap.CurrentProvider|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $currentPath -Encoding UTF8}
    else{Remove-Item -LiteralPath $currentPath -ErrorAction SilentlyContinue}
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    foreach ($a in @($snap.Adapters)) {
        $adapter=Get-NetAdapter -ErrorAction Stop | Where-Object { $_.InterfaceGuid.ToString().Trim('{}') -eq $a.InterfaceGuid.ToString().Trim('{}') } | Select-Object -First 1
        $static=Get-StaticDnsServers -Adapter $adapter
        if ($a.PSObject.Properties.Name -contains 'Automatic') {
            foreach ($family in @('IPv4','IPv6')) {
                if ((@($a.("Static$family")) -join ',') -ne (@($static.$family) -join ',')) { throw "DNS restore verification failed for $($a.Name) $family." }
            }
        } else {
            foreach ($family in @('IPv4','IPv6')) {
                if ((@($a.$family) -join ',') -ne (@($static.$family) -join ',')) { throw "Legacy DNS restore verification failed for $($a.Name) $family." }
            }
        }
    }
    foreach ($entry in @($snap.Encryption)) {
        $actual=Get-DohStateForServer $entry.ServerAddress
        if (-not $actual -or $actual.DohTemplate -ne $entry.DohTemplate -or $actual.AllowFallbackToUdp -ne $entry.AllowFallbackToUdp -or $actual.AutoUpgrade -ne $entry.AutoUpgrade) { throw "DoH restore verification failed for $($entry.ServerAddress)." }
    }
    Write-Status OK ("DNS state restored and verified from {0}" -f $path)
}
function Reset-Dhcp {
    Assert-Admin;Initialize-State
    $snapshotPath=New-DnsSnapshot
    try{
        foreach($a in Get-Adapters){
            Set-AdapterDnsFamilies -Index $a.ifIndex
            $actual=Get-StaticDnsServers -Adapter $a
            if (@($actual.IPv4).Count -or @($actual.IPv6).Count) { throw "Automatic DNS read-back failed for $($a.Name)." }
            Write-Status OK ("{0}: DNS returned to DHCP/automatic" -f $a.Name)
        }
        Remove-Item -LiteralPath (Join-Path $StateRoot 'current_provider.json') -ErrorAction SilentlyContinue
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Write-Status OK 'Automatic DNS restored. Global DoH entries were preserved for other adapters.'
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
    Write-Host '  Mullvad public encrypted DNS ends November 2, 2026.' -ForegroundColor Yellow
    Write-Host '  Quad9 is the recommended ongoing provider.' -ForegroundColor Gray
    Write-Host '  [1] Quad9 Secure           Malware blocking, no ad blocking'
    Write-Host '  [2] AdGuard DNS            Ads and trackers'
    Write-Host '  [V] Verify current DoH configuration'
    Write-Host '  [R] Restore exact previous DNS state'
    Write-Host '  [D] Return active adapters to DHCP DNS'
    Write-Host '  [0] Exit'
    Write-Host ''
}

if ($Action -eq 'Library') { return }
if($Action -ne 'Menu'){
    try {
    switch($Action){
        'Quad9'{Set-Provider Quad9}'AdGuard'{Set-Provider AdGuard}'Mullvad'{Set-Provider Mullvad}'MullvadAdBlock'{Set-Provider MullvadAdBlock}
        'MullvadBase'{Set-Provider MullvadBase}'MullvadExtended'{Set-Provider MullvadExtended}'MullvadFamily'{Set-Provider MullvadFamily}'MullvadAll'{Set-Provider MullvadAll}
        'Verify'{if (-not (Test-Configuration)) { exit 1 }}'Restore'{Restore-Snapshot -Path $SnapshotPath}'DHCP'{Reset-Dhcp}
    }
    } catch { Write-DnsDiagnostic 'FAIL' $_.Exception.Message; throw }
    exit
}
while($true){
    Show-Menu;$c=(Read-Host '  Select').Trim().ToUpperInvariant();Write-DnsDiagnostic 'DEBUG' "Selected action: $c"
    try{switch($c){'1'{Set-Provider Quad9}'2'{Set-Provider AdGuard}'V'{Test-Configuration|Out-Null}'R'{Restore-Snapshot}'D'{Reset-Dhcp}'0'{break}default{Write-Status WARN 'Invalid selection.'}}}catch{Write-Status FAIL $_.Exception.Message}
    if($c -eq '0'){break};Write-Host '';Read-Host '  Press Enter to continue'|Out-Null
}
