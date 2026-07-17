<#
.SYNOPSIS
    Revert DNS to DHCP/automatic and clear custom DoH (HTTPS) templates we registered.
.DESCRIPTION
    - Sets every active physical adapter back to DNS from DHCP
    - Removes Quad9 / Mullvad DoH server registrations added by DNS_Set_Encrypted_DoH.ps1
    - Resets EnableAutoDoh preference
    - Flushes DNS cache
.NOTES
    Requires Administrator.
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host '   REVERT DNS TO DHCP (automatic) + clear custom DoH' -ForegroundColor Yellow
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host ''

$ourServers = @(
    '9.9.9.9', '149.112.112.112', '2620:fe::fe', '2620:fe::9',
    '194.242.2.3', '2a07:e340::3'
)

# ---------------------------------------------------------
# 1. Adapters -> DHCP DNS
# ---------------------------------------------------------
Write-Host '  [1/3] Setting adapters to obtain DNS from DHCP...' -ForegroundColor Cyan
$adapters = @()
try {
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    if ($adapters.Count -eq 0) {
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|VPN|TAP|Wintun|Hyper-V|vEthernet|Loopback'
        })
    }
} catch { }

if ($adapters.Count -eq 0) {
    Write-Host '  [!!] No active adapters found - trying common names via netsh...' -ForegroundColor Yellow
    foreach ($name in @('Ethernet', 'Wi-Fi', 'Ethernet 2', 'Wi-Fi 2')) {
        $null = netsh interface ipv4 set dnsservers name="$name" dhcp 2>&1
        $null = netsh interface ipv6 set dnsservers name="$name" dhcp 2>&1
    }
} else {
    foreach ($adapter in $adapters) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
            Write-Host "  [OK] $($adapter.Name) -> DNS from DHCP" -ForegroundColor Green
        } catch {
            $null = netsh interface ipv4 set dnsservers name="$($adapter.Name)" dhcp 2>&1
            $null = netsh interface ipv6 set dnsservers name="$($adapter.Name)" dhcp 2>&1
            Write-Host "  [OK] $($adapter.Name) -> DNS from DHCP (netsh)" -ForegroundColor Green
        }
    }
}
Write-Host ''

# ---------------------------------------------------------
# 2. Remove our DoH registrations
# ---------------------------------------------------------
Write-Host '  [2/3] Removing custom DoH HTTPS templates...' -ForegroundColor Cyan
if (Get-Command Remove-DnsClientDohServerAddress -ErrorAction SilentlyContinue) {
    foreach ($ip in $ourServers) {
        try {
            $exists = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
            if ($exists) {
                # Only remove if it points at our known templates (don't nuke user custom entries for other IPs)
                $tpl = $exists.DohTemplate
                if ($tpl -match 'quad9\.net|mullvad\.net') {
                    Remove-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction Stop
                    Write-Host "  [OK] Removed DoH for $ip ($tpl)" -ForegroundColor Green
                } else {
                    Write-Host "  [>>] Kept $ip (template not ours: $tpl)" -ForegroundColor DarkGray
                }
            }
        } catch {
            Write-Host "  [!!] Could not remove DoH for $ip : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host '  [>>] DoH cmdlets not available - skipped template cleanup' -ForegroundColor DarkGray
}

# Reset EnableAutoDoh to Windows default (opportunistic / 0)
try {
    $dnsParam = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
    if (Test-Path $dnsParam) {
        $cur = (Get-ItemProperty -Path $dnsParam -Name 'EnableAutoDoh' -ErrorAction SilentlyContinue).EnableAutoDoh
        if ($null -ne $cur) {
            Remove-ItemProperty -Path $dnsParam -Name 'EnableAutoDoh' -Force -ErrorAction SilentlyContinue
            Write-Host '  [OK] EnableAutoDoh preference cleared (Windows default)' -ForegroundColor Green
        }
    }
} catch { }
Write-Host ''

# ---------------------------------------------------------
# 3. Flush
# ---------------------------------------------------------
Write-Host '  [3/3] Flushing DNS cache...' -ForegroundColor Cyan
$null = ipconfig /flushdns 2>&1
Write-Host '  [OK] DNS cache flushed' -ForegroundColor Green
Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host '   DNS reverted to automatic (DHCP / router).' -ForegroundColor Green
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host ''

exit 0
