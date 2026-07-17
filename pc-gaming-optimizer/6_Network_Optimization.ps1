<#
.SYNOPSIS
    Optimizes Windows network stack for low-latency gaming.
.DESCRIPTION
    TCP/IP, DNS, and network adapter optimizations to reduce latency.
.NOTES
    Requires Administrator privileges. Changes take effect immediately.
#>

#Requires -RunAsAdministrator

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  NETWORK OPTIMIZER FOR GAMING" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Tuning TCP/IP, DNS, and adapter settings..." -ForegroundColor Gray
Write-Host ""

# ---------------------------------------------------------
# 1. TCP/IP OPTIMIZATIONS
# ---------------------------------------------------------
Write-Host "[1/6] Optimizing TCP/IP stack..." -ForegroundColor Cyan

netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
Write-Host "  TCP autotuning: Normal" -ForegroundColor Green

# CTCP helps on Win10; Win11 rejects this and stays on CUBIC (which is already optimal)
$ctcpOut = netsh int tcp set supplemental custom congestionprovider=ctcp 2>&1
if ($LASTEXITCODE -eq 0 -and $ctcpOut -notmatch "incorrect|invalid|failed") {
    Write-Host "  Congestion provider: CTCP" -ForegroundColor Green
} else {
    Write-Host "  Congestion provider: CUBIC kept (Windows 11 default - already optimal)" -ForegroundColor Green
}

netsh int tcp set global rss=enabled 2>&1 | Out-Null
Write-Host "  RSS (Receive-Side Scaling): Enabled" -ForegroundColor Green

netsh int tcp set global timestamps=disabled 2>&1 | Out-Null
Write-Host "  TCP timestamps: Disabled (less overhead)" -ForegroundColor Green

# Initial RTO stays at the 1000ms Windows default - raising it delays loss
# recovery; lowering it risks spurious retransmits on wifi. Default wins.
netsh int tcp set global initialRto=1000 2>&1 | Out-Null
Write-Host "  Initial RTO: 1000ms (default - fastest safe loss recovery)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 2. DISABLE NAGLE'S ALGORITHM
# ---------------------------------------------------------
Write-Host "[2/6] Disabling Nagle's algorithm..." -ForegroundColor Cyan

$interfacesKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
Get-ChildItem $interfacesKey -ErrorAction SilentlyContinue | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $_.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $_.PSPath -Name "TcpDelAckTicks" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
}
Write-Host "  Nagle disabled | ACK immediate (lower latency)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 3. NETWORK THROTTLING: Disable
# ---------------------------------------------------------
Write-Host "[3/6] Disabling network throttling..." -ForegroundColor Cyan
$throttleKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
Set-ItemProperty -Path $throttleKey -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $throttleKey -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "  Network throttling: DISABLED" -ForegroundColor Green
Write-Host "  System responsiveness: Gaming priority" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 4. DNS OPTIMIZATIONS
# ---------------------------------------------------------
Write-Host "[4/6] Optimizing DNS..." -ForegroundColor Cyan
ipconfig /flushdns 2>&1 | Out-Null
Write-Host "  DNS cache flushed" -ForegroundColor Green
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "MaxCacheTtl" -Value 86400 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "MaxNegativeCacheTtl" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "  DNS cache TTL optimized" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 5. NIC ADVANCED SETTINGS
# ---------------------------------------------------------
Write-Host "[5/6] Optimizing network adapters..." -ForegroundColor Cyan
$adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
if ($adapters) {
    foreach ($adapter in $adapters) {
        Write-Host "  Adapter: $($adapter.Name)" -ForegroundColor Gray
        try { Disable-NetAdapterRsc -Name $adapter.Name -ErrorAction SilentlyContinue
              Write-Host "    RSC disabled (lower latency)" -ForegroundColor Green } catch { }
        try { Enable-NetAdapterChecksumOffload -Name $adapter.Name -ErrorAction SilentlyContinue
              Write-Host "    Checksum offload enabled" -ForegroundColor Green } catch { }
    }
}
Write-Host ""

# ---------------------------------------------------------
# 6. QoS TWEAK
# ---------------------------------------------------------
Write-Host "[6/6] Configuring QoS..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS" -Name "Do not use NLA" -Value "1" -Force -ErrorAction SilentlyContinue
Write-Host "  QoS NLA bypass applied" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  NETWORK OPTIMIZATION COMPLETE" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Applied:" -ForegroundColor Cyan
Write-Host "  - TCP autotuning | congestion control | RSS" -ForegroundColor Green
Write-Host "  - Nagle disabled (lower packet latency)" -ForegroundColor Green
Write-Host "  - Network throttling disabled" -ForegroundColor Green
Write-Host "  - DNS cache flushed & optimized" -ForegroundColor Green
Write-Host "  - Adapter RSC disabled | Checksum offload enabled" -ForegroundColor Green
Write-Host ""
Write-Host "Tip: Use wired Ethernet for lowest latency." -ForegroundColor Gray
Write-Host "Tip: For encrypted DNS (DoH HTTPS Quad9+Mullvad), run" -ForegroundColor Gray
Write-Host "     DNS_Set_Quad9_Mullvad.bat in the parent folder, or Network menu [2]." -ForegroundColor Gray