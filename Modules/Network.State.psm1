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
    foreach ($family in @(@{Id=2;Servers=$IPv4},@{Id=23;Servers=$IPv6})) {
        $inputObject=Get-DnsClientServerAddress -InterfaceIndex $Index -ErrorAction Stop | Where-Object { [int]$_.AddressFamily -eq $family.Id }
        if (-not $inputObject) {
            if (@($family.Servers).Count) { throw "Adapter $Index does not expose address family $($family.Id)." }
            continue
        }
        if (@($family.Servers).Count) { Set-DnsClientServerAddress -InputObject $inputObject -ServerAddresses $family.Servers -ErrorAction Stop }
        else { Set-DnsClientServerAddress -InputObject $inputObject -ResetServerAddresses -ErrorAction Stop }
    }
}
Export-ModuleMember -Function Set-AdapterDnsFamilies,Get-AdapterStaticDnsServers
