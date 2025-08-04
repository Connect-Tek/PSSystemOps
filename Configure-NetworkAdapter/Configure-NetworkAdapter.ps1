function Configure-NetworkAdapter {
<#
.SYNOPSIS
    Configure a network adapter with either a static IP or DHCP.

.DESCRIPTION
    This script sets a static IP address or enables DHCP on a local network adapter.
    It removes any existing IP configuration before applying the new one.

    ⚠️ This script only works on the **local computer**.
    Remote configuration was intentionally left out to avoid issues with
    losing remote connectivity mid-script (e.g. during IP changes).

.PARAMETER AdapterName
    The name of the network adapter (e.g. "Ethernet", "Wi-Fi").

.PARAMETER IPAddress
    The static IP address to assign. Required if -Dhcp is not used.

.PARAMETER SubnetMask
    The subnet mask (e.g. 255.255.255.0). Required if -Dhcp is not used.

.PARAMETER DefaultGateway
    (Optional) The default gateway address.

.PARAMETER DNSServer
    (Optional) One or more DNS server addresses.

.PARAMETER Dhcp
    Use this switch to enable DHCP instead of static configuration.
    When -Dhcp is used, all other parameters are ignored.

.EXAMPLE
    Configure-NetworkAdapter -AdapterName "Ethernet" -Dhcp

    Enables DHCP on the "Ethernet" adapter.

.EXAMPLE
    Configure-NetworkAdapter `
        -AdapterName "Ethernet" `
        -IPAddress 192.168.1.50 `
        -SubnetMask 255.255.255.0 `
        -DefaultGateway 192.168.1.1 `
        -DNSServer 192.168.1.10,8.8.8.8

    Sets a static IP address and DNS on the "Ethernet" adapter.

.NOTES
    Author: ConnectTek
    Requires: Administrator rights
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AdapterName,

        [Parameter()]
        [System.Net.IPAddress]$IPAddress,

        [Parameter()]
        [System.Net.IPAddress]$SubnetMask,

        [Parameter()]
        [System.Net.IPAddress]$DefaultGateway,

        [Parameter()]
        [System.Net.IPAddress[]]$DNSServer,

        [switch]$Dhcp
    )

    if ($Dhcp) {
        # Remove existing IP and route
        Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceAlias $AdapterName -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        # Enable DHCP
        Set-NetIPInterface -InterfaceAlias $AdapterName -Dhcp Enabled -ErrorAction Stop
        Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses -ErrorAction Stop

        Write-Host "DHCP enabled on '$AdapterName'" -ForegroundColor Cyan
        return
    }

    if (-not $IPAddress -or -not $SubnetMask) {
        Write-Warning "Static IP and SubnetMask are required without -Dhcp"
        return
    }

    $binaryMask = ($SubnetMask.GetAddressBytes() |
        ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
    $prefixLength = ($binaryMask -split '0')[0].Length

    # Remove existing IP and route
    Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetRoute -InterfaceAlias $AdapterName -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

    # Apply static IP
    $ipParams = @{
        InterfaceAlias = $AdapterName
        AddressFamily  = 'IPv4'
        IPAddress      = $IPAddress
        PrefixLength   = $prefixLength
    }
    if ($DefaultGateway) {
        $ipParams.DefaultGateway = $DefaultGateway
    }

    New-NetIPAddress @ipParams

    # Set DNS
    if ($DNSServer) {
        Set-DnsClientServerAddress -InterfaceAlias $AdapterName `
            -ServerAddresses ($DNSServer.IPAddressToString)
    }

    Write-Host "Static IP configured on '$AdapterName'"
}
 

Configure-NetworkAdapter -AdapterName "Ethernet" -Dhcp
