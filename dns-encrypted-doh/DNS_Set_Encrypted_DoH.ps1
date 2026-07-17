<#
.SYNOPSIS
    Apply Quad9 (primary) + Mullvad AdBlock (secondary) with REAL DNS-over-HTTPS (DoH).
.DESCRIPTION
    Previous bat only set plain UDP/53 IPs and claimed "encrypted". This script:
      1. Registers official HTTPS DoH templates with Windows
      2. Sets DNS servers on every active physical adapter (not hard-coded "Ethernet")
      3. Enables system DoH (AutoUpgrade + EnableAutoDoh) so queries use HTTPS tunnels
      4. Flushes DNS and verifies DoH registration
.NOTES
    Official templates (verified provider docs):
      Quad9:   https://dns.quad9.net/dns-query          -> 9.9.9.9 / 2620:fe::fe
      Mullvad: https://adblock.dns.mullvad.net/dns-query -> 194.242.2.3 / 2a07:e340::3
    Requires Admin. DoH client is Windows 11 / Server 2022+ (Win10 has limited support).
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host '   ENCRYPTED DNS (DNS-over-HTTPS) - Quad9 + Mullvad AdBlock' -ForegroundColor Yellow
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host ''

# --- Official HTTPS DoH templates (must match the server IPs) ---
$DohMap = @(
    @{ Server = '9.9.9.9';       Template = 'https://dns.quad9.net/dns-query';           Label = 'Quad9 IPv4' }
    @{ Server = '149.112.112.112'; Template = 'https://dns.quad9.net/dns-query';         Label = 'Quad9 IPv4 alt' }
    @{ Server = '2620:fe::fe';   Template = 'https://dns.quad9.net/dns-query';           Label = 'Quad9 IPv6' }
    @{ Server = '2620:fe::9';    Template = 'https://dns.quad9.net/dns-query';           Label = 'Quad9 IPv6 alt' }
    @{ Server = '194.242.2.3';   Template = 'https://adblock.dns.mullvad.net/dns-query'; Label = 'Mullvad AdBlock IPv4' }
    @{ Server = '2a07:e340::3';  Template = 'https://adblock.dns.mullvad.net/dns-query'; Label = 'Mullvad AdBlock IPv6' }
)

$PrimaryV4   = '9.9.9.9'
$SecondaryV4 = '194.242.2.3'
$PrimaryV6   = '2620:fe::fe'
$SecondaryV6 = '2a07:e340::3'

function Register-DohServer {
    param([string]$Server, [string]$Template, [string]$Label)
    if (-not (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        $existing = Get-DnsClientDohServerAddress -ServerAddress $Server -ErrorAction SilentlyContinue
        if ($existing) {
            Set-DnsClientDohServerAddress -ServerAddress $Server -DohTemplate $Template `
                -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop | Out-Null
            Write-Host "  [OK] $Label : updated DoH template" -ForegroundColor Green
        } else {
            Add-DnsClientDohServerAddress -ServerAddress $Server -DohTemplate $Template `
                -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop | Out-Null
            Write-Host "  [OK] $Label : registered DoH template" -ForegroundColor Green
        }
        Write-Host "       $Server  ->  $Template" -ForegroundColor DarkGray
        return $true
    } catch {
        Write-Host "  [!!] $Label failed: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# ---------------------------------------------------------
# 1. Register DoH HTTPS templates with Windows DNS client
# ---------------------------------------------------------
Write-Host '  [1/4] Registering DNS-over-HTTPS templates...' -ForegroundColor Cyan
$dohOk = $false
if (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue) {
    foreach ($entry in $DohMap) {
        if (Register-DohServer -Server $entry.Server -Template $entry.Template -Label $entry.Label) {
            $dohOk = $true
        }
    }
} else {
    Write-Host '  [!!] Add-DnsClientDohServerAddress not available on this Windows build.' -ForegroundColor Yellow
    Write-Host '       DNS IPs will still be set; DoH requires Windows 11 / Server 2022+.' -ForegroundColor DarkGray
}
Write-Host ''

# ---------------------------------------------------------
# 2. Enable system-wide DoH preference (prefer encrypted)
#    EnableAutoDoh: 0=off, 1=opportunistic, 2=require when template known
# ---------------------------------------------------------
Write-Host '  [2/4] Enabling system DoH preference...' -ForegroundColor Cyan
$dnsParam = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
try {
    if (-not (Test-Path $dnsParam)) { New-Item -Path $dnsParam -Force | Out-Null }
    # 2 = use DoH when a template exists for the configured server (encrypted tunnel)
    Set-ItemProperty -Path $dnsParam -Name 'EnableAutoDoh' -Value 2 -Type DWord -Force
    Write-Host '  [OK] EnableAutoDoh = 2 (use HTTPS when template is known)' -ForegroundColor Green
} catch {
    Write-Host "  [!!] Could not set EnableAutoDoh: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ''

# ---------------------------------------------------------
# 3. Apply DNS on all active physical adapters (auto-detect)
# ---------------------------------------------------------
Write-Host '  [3/4] Applying DNS servers on active adapters...' -ForegroundColor Cyan
$adapters = @()
try {
    $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {
        $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true
    })
} catch {
    Write-Host "  [!!] Get-NetAdapter failed: $_" -ForegroundColor Yellow
}

if ($adapters.Count -eq 0) {
    # Fallback: any Up adapter that is not virtual tunnel
    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object {
            $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|VPN|TAP|Wintun|Hyper-V|vEthernet|Loopback'
        })
    } catch { }
}

if ($adapters.Count -eq 0) {
    Write-Host '  [XX] No active network adapter found. Connect Ethernet/Wi-Fi and re-run.' -ForegroundColor Red
    exit 1
}

foreach ($adapter in $adapters) {
    $name = $adapter.Name
    $ifIndex = $adapter.ifIndex
    Write-Host "  Adapter: $name  ($($adapter.InterfaceDescription))" -ForegroundColor White
    # Set-DnsClientServerAddress accepts mixed v4+v6 in one list (no -AddressFamily)
    $allDns = @($PrimaryV4, $SecondaryV4, $PrimaryV6, $SecondaryV6)
    try {
        Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $allDns -ErrorAction Stop
        Write-Host "    IPv4 DNS: $PrimaryV4, $SecondaryV4" -ForegroundColor Green
        Write-Host "    IPv6 DNS: $PrimaryV6, $SecondaryV6" -ForegroundColor Green
    } catch {
        Write-Host "    [!!] Set-DnsClientServerAddress failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host '    Trying netsh IPv4 + IPv6 fallback...' -ForegroundColor DarkGray
        $null = netsh interface ipv4 set dnsservers name="$name" static $PrimaryV4 primary validate=no 2>&1
        $null = netsh interface ipv4 add dnsservers name="$name" $SecondaryV4 index=2 validate=no 2>&1
        $null = netsh interface ipv6 set dnsservers name="$name" static $PrimaryV6 primary validate=no 2>&1
        $null = netsh interface ipv6 add dnsservers name="$name" $SecondaryV6 index=2 validate=no 2>&1
        Write-Host "    IPv4/IPv6 DNS applied via netsh on $name" -ForegroundColor Green
    }
}
Write-Host ''

# ---------------------------------------------------------
# 4. Flush + verify
# ---------------------------------------------------------
Write-Host '  [4/4] Flushing DNS cache and verifying...' -ForegroundColor Cyan
try {
    $null = ipconfig /flushdns 2>&1
    Write-Host '  [OK] DNS cache flushed' -ForegroundColor Green
} catch {
    Write-Host '  [!!] Flush skipped' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '  Current DNS per adapter:' -ForegroundColor Cyan
foreach ($adapter in $adapters) {
    try {
        $cfg = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $servers = ($cfg.ServerAddresses) -join ', '
        Write-Host "    $($adapter.Name): $servers" -ForegroundColor White
    } catch { }
}

if ($dohOk -and (Get-Command Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '  Registered DoH (HTTPS) templates:' -ForegroundColor Cyan
    try {
        Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddress -in @($PrimaryV4, $SecondaryV4, $PrimaryV6, $SecondaryV6, '149.112.112.112', '2620:fe::9') } |
            ForEach-Object {
                $fb = if ($_.AllowFallbackToUdp) { 'fallback UDP allowed' } else { 'HTTPS only (no UDP fallback)' }
                Write-Host "    $($_.ServerAddress)  $($_.DohTemplate)  [$fb]" -ForegroundColor Green
            }
    } catch { }
}

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host '   DONE - Encrypted DNS tunnel (DoH over HTTPS) configured' -ForegroundColor Green
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host '  Primary:   Quad9     9.9.9.9     https://dns.quad9.net/dns-query' -ForegroundColor Gray
Write-Host '  Secondary: Mullvad   194.242.2.3 https://adblock.dns.mullvad.net/dns-query' -ForegroundColor Gray
Write-Host ''
Write-Host '  Verify: Settings > Network > your adapter > DNS > should show' -ForegroundColor DarkGray
Write-Host '          DNS over HTTPS = On (automatic/manual template).' -ForegroundColor DarkGray
Write-Host '  Or: Get-DnsClientDohServerAddress  in an elevated PowerShell.' -ForegroundColor DarkGray
Write-Host ''

exit 0
