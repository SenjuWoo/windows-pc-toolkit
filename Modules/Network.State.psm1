#requires -version 5.1
$ErrorActionPreference='Stop'

function Get-AdapterStaticDnsServers {
    param([Parameter(Mandatory)]$Adapter)
    $guid=([guid]$Adapter.InterfaceGuid).ToString()
    $result=[ordered]@{IPv4=@();IPv6=@()}
    foreach ($family in @('IPv4','IPv6')) {
        $service=if ($family -eq 'IPv4') { 'Tcpip' } else { 'Tcpip6' }
        $path="HKLM:\SYSTEM\CurrentControlSet\Services\$service\Parameters\Interfaces\{$guid}"
        if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) { continue }
        $key=Get-Item -LiteralPath $path -ErrorAction Stop
        if ($key.GetValueNames() -notcontains 'NameServer') { continue }
        $raw=@($key.GetValue('NameServer',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)) -join ','
        $result[$family]=@($raw -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    [pscustomobject]$result
}

function Set-AdapterDnsFamilies {
    param([int]$Index,[AllowEmptyCollection()][string[]]$IPv4=@(),[AllowEmptyCollection()][string[]]$IPv6=@())
    $addresses=@(Get-DnsClientServerAddress -InterfaceIndex $Index -ErrorAction Stop)
    if (-not $addresses.Count) { throw "Adapter $Index exposes no DNS address families." }
    $changes=foreach ($family in @(@{Id=2;Servers=$IPv4},@{Id=23;Servers=$IPv6})) {
        $inputObject=$addresses | Where-Object { [int]$_.AddressFamily -eq $family.Id }
        if (-not $inputObject) {
            if (@($family.Servers).Count) { throw "Adapter $Index does not expose address family $($family.Id)." }
            continue
        }
        @{InputObject=$inputObject;Servers=$family.Servers}
    }
    foreach ($change in $changes) {
        if (@($change.Servers).Count) { Set-DnsClientServerAddress -InputObject $change.InputObject -ServerAddresses $change.Servers -ErrorAction Stop }
        else { Set-DnsClientServerAddress -InputObject $change.InputObject -ResetServerAddresses -ErrorAction Stop }
    }
}
Export-ModuleMember -Function Set-AdapterDnsFamilies,Get-AdapterStaticDnsServers
