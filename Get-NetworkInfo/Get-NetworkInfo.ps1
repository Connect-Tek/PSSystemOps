function Get-NetworkInfo {
<#
.SYNOPSIS
    Retrieves detailed network adapter information from one or more computers.

.DESCRIPTION
    This function queries one or more local or remote computers for network adapter information,
    including IP addresses, MAC address, driver details, DNS servers, default gateways, and more.

    Optionally, the results can be filtered by adapter name and exported in various formats: 
    TXT, JSON, CSV, or XML.

.PARAMETER AdapterName
    Optional string to filter specific network adapters by name (wildcard supported).

.PARAMETER ComputerName
    One or more computer names to retrieve adapter information from.
    Defaults to the local computer if not specified.

.PARAMETER ExportFormat
    The format to export the collected data to. Supported options: CSV, JSON, XML, TXT.

.PARAMETER ExportPath
    Path to the directory where the exported file should be saved.
    If not specified, defaults to the system TEMP directory.

.EXAMPLE
    Get-NetworkInfo

    Retrieves all adapter info from the local machine.

.EXAMPLE
    Get-NetworkInfo -AdapterName "Ethernet" -ExportFormat JSON -ExportPath "C:\Exports"

    Gets info for adapters matching "Ethernet" and exports to JSON in C:\Exports.

.EXAMPLE
    Get-NetworkInfo -ComputerName "Server1","Server2" -ExportFormat TXT

    Queries Server1 and Server2, then exports results to a TXT file in the temp folder.

.NOTES
    Author: ConnectTek
    Created: 2025-07-31
    Requirements: PowerShell 5.1+, admin rights if querying remote systems
#>

    [CmdletBinding()]
    # ============================================
    # Defining Parameters
    # ============================================
    param (
        # Optional: filter by adapter name
        [string]$AdapterName,

        # List of computer names (default to local machine)
        [string[]]$ComputerName = $env:COMPUTERNAME,

        # Format to export the data (CSV, JSON, XML, TXT)
        [ValidateSet('CSV', 'JSON', 'XML', 'TXT')]
        [string]$ExportFormat,

        # Directory path to export the file to
        [string]$ExportPath
    )

    # ============================================
    # Initialize output container
    # Using [ordered]@{} to keep computer order in export
    # ============================================
    $outputStructure = [ordered]@{}

    # ============================================
    # SECTION: Loop through each computer name
    # ============================================
    foreach ($comp in $ComputerName) {
        try {
            Write-Host "`n=== Computer: $comp ===`n" -ForegroundColor Cyan

            # Check if querying local or remote system
            if ($comp -eq $env:COMPUTERNAME) {
                $adapters = Get-NetAdapter -ErrorAction Stop
            } else {
                # Create CIM session to remote machine
                $session = New-CimSession -ComputerName $comp
                $adapters = Get-NetAdapter -CimSession $session -ErrorAction Stop
            }

            # Filter adapters by name if specified
            if ($AdapterName) {
                $adapters = $adapters | Where-Object { $_.InterfaceAlias -like "*$AdapterName*" }
                if (-not $adapters) {
                    Write-Warning "No adapters found matching name: $AdapterName on $comp"
                    continue
                }
            }
        } catch {
            Write-Error "Failed to retrieve network adapter info from ${comp}: $_"
            continue
        }

        # List to hold all adapter info for current computer
        $adapterList = @()

        # ============================================
        # SECTION: Process each network adapter
        # ============================================
        foreach ($adapter in $adapters) {
            try {
                $index = $adapter.InterfaceIndex

                # Query network information (IP, gateway, DNS)
                if ($comp -eq $env:COMPUTERNAME) {
                    $ipInfo     = Get-NetIPAddress -InterfaceIndex $index -ErrorAction SilentlyContinue
                    $gateway    = Get-NetRoute -InterfaceIndex $index -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
                    $dnsServers = Get-DnsClientServerAddress -InterfaceIndex $index -ErrorAction SilentlyContinue
                } else {
                    $ipInfo     = Get-NetIPAddress -CimSession $session -InterfaceIndex $index -ErrorAction SilentlyContinue
                    $gateway    = Get-NetRoute -CimSession $session -InterfaceIndex $index -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
                    $dnsServers = Get-DnsClientServerAddress -CimSession $session -InterfaceIndex $index -ErrorAction SilentlyContinue
                }

                # Separate IPv4 and IPv6 info
                $ipv4 = $ipInfo | Where-Object { $_.AddressFamily -eq 'IPv4' }
                $ipv6 = $ipInfo | Where-Object { $_.AddressFamily -eq 'IPv6' }

                # Convert CIDR prefix to traditional subnet mask format (e.g., 255.255.255.0)
                $subnetMask = ($ipv4.PrefixLength | ForEach-Object {
                    $binary = ("1" * $_).PadRight(32, '0')
                    $octets = ($binary -split '(.{8})' | Where-Object { $_ }) | ForEach-Object { [Convert]::ToInt32($_, 2) }
                    $octets -join '.'
                })

                # Create object with adapter details
                $adapterInfo = [PSCustomObject]@{
                    'Adapter Name'     = $adapter.InterfaceAlias
                    'Interface Index'  = $index
                    'Status'           = $adapter.Status
                    'MAC Address'      = $adapter.MacAddress
                    'Link Speed'       = $adapter.LinkSpeed
                    'Driver Name'      = $adapter.DriverName
                    'Driver Version'   = $adapter.DriverVersion
                    'Driver Date'      = $adapter.DriverDate
                    'Driver Info'      = $adapter.DriverInformation
                    'IPv4 Address'     = ($ipv4.IPAddress -join ', ')
                    'IPv4 Subnet'      = $subnetMask
                    'IPv6 Address'     = ($ipv6.IPAddress -join ', ')
                    'Default Gateway'  = ($gateway.NextHop -join ', ')
                    'DNS Servers'      = ($dnsServers.ServerAddresses -join ', ')
                }

                # Show adapter on screen
                $adapterInfo

                # Add to current computer's list
                $adapterList += $adapterInfo
            } catch {
                Write-Warning "Failed to process adapter '$($adapter.InterfaceAlias)' on $comp $_"
            }
        }

        # Add current computer and its adapter list to final output
        $outputStructure[$comp] = $adapterList
    }

    # ============================================
    # SECTION: Export output to file (if specified)
    # ============================================
    if (($ExportFormat -or $ExportPath) -and $outputStructure.Count -gt 0) {

        # Determine output directory
        $exportDirectory = if ($ExportPath) { $ExportPath } else { $env:TEMP }

        # Create directory if it doesn't exist
        if (-not (Test-Path $exportDirectory)) {
            New-Item -Path $exportDirectory -ItemType Directory -Force | Out-Null
        }

        # Generate file name with timestamp and extension
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $fileExtension = switch ($ExportFormat) {
            'CSV'  { 'csv' }
            'JSON' { 'json' }
            'XML'  { 'xml' }
            'TXT'  { 'txt' }
        }

        $exportFilePath = Join-Path $exportDirectory "NetworkInfo_$timestamp.$fileExtension"

        # ---------- EXPORT TO TXT ----------
        if ($ExportFormat -eq 'TXT') {
            $textOutput = foreach ($comp in $outputStructure.Keys) {
                "=== $comp ===`n" +
                ($outputStructure[$comp] | Format-List | Out-String) +
                ('-' * 40) + "`n"
            }
            $textOutput | Set-Content -Path $exportFilePath -Encoding UTF8
        }

        # ---------- EXPORT TO JSON ----------
        elseif ($ExportFormat -eq 'JSON') {
            $outputStructure | ConvertTo-Json -Depth 5 | Set-Content -Path $exportFilePath -Encoding UTF8
        }

        # ---------- EXPORT TO CSV ----------
        elseif ($ExportFormat -eq 'CSV') {
            $csvOutput = @()
            foreach ($comp in $outputStructure.Keys) {
                $csvOutput += "=== $comp ==="
                $csvOutput += ($outputStructure[$comp] | ConvertTo-Csv -NoTypeInformation)
                $csvOutput += ""
            }
            $csvOutput | Set-Content -Path $exportFilePath -Encoding UTF8
        }

        # ---------- EXPORT TO XML ----------
        elseif ($ExportFormat -eq 'XML') {
            $xmlDoc = New-Object System.Xml.XmlDocument
            $xmlRoot = $xmlDoc.CreateElement("NetworkInfo")
            $xmlDoc.AppendChild($xmlRoot) | Out-Null

            foreach ($comp in $outputStructure.Keys) {
                $computerElement = $xmlDoc.CreateElement("Computer")
                $computerElement.SetAttribute("Name", $comp)

                foreach ($adapterData in $outputStructure[$comp]) {
                    $adapterElement = $xmlDoc.CreateElement("Adapter")
                    foreach ($property in $adapterData.PSObject.Properties) {
                        $adapterPropertyElement = $xmlDoc.CreateElement($property.Name.Replace(" ", ""))
                        $adapterPropertyElement.InnerText = $property.Value
                        $adapterElement.AppendChild($adapterPropertyElement) | Out-Null
                    }
                    $computerElement.AppendChild($adapterElement) | Out-Null
                }

                $xmlRoot.AppendChild($computerElement) | Out-Null
            }

            $xmlDoc.Save($exportFilePath)
        }

        # Output location of export file
        Write-Host "`nExported file saved to:`n$($exportFilePath)`n" -ForegroundColor Green
    }
}
