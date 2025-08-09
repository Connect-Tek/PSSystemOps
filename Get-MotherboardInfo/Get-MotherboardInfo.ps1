function Get-MotherboardInfo {
<#
.SYNOPSIS
    Retrieves motherboard (baseboard) details from local or remote computers.

.DESCRIPTION
    Uses WMI/CIM (Win32_BaseBoard) to list motherboard details per computer, including manufacturer, product name, serial number, version, and part number.
    Results are grouped by computer for console output and can optionally be exported in CSV, JSON, XML, TXT, or HTML formats.

.PARAMETER ComputerName
    One or more computer names to query.
    Defaults to the local computer if not specified.

.PARAMETER ExportFormat
    Optional export format. Supported values: CSV, JSON, XML, TXT, HTML.

.PARAMETER ExportPath
    Optional directory path for saving the export file. If omitted, a temp directory is used.

.EXAMPLE
    Get-MotherboardInfo
    Displays motherboard details for the local computer.

.EXAMPLE
    Get-MotherboardInfo -ComputerName "Server01","Server02"
    Retrieves motherboard details from multiple remote computers.

.EXAMPLE
    Get-MotherboardInfo -ExportFormat CSV -ExportPath "C:\Reports"
    Retrieves local motherboard info and exports it to a CSV file in the specified folder.

.EXAMPLE
    Get-MotherboardInfo -ComputerName "PC01" -ExportFormat HTML
    Retrieves motherboard info from PC01 and saves an HTML report to the temp directory.

.LIMITATIONS
    - Some systems may not report certain fields (e.g., SerialNumber or PartNumber could be blank).
    - Remote execution requires working network connectivity and WinRM configuration.
    - Export directory must be writable; the script attempts to create it if it doesn’t exist.

.REQUIREMENTS
    - PowerShell 5.1 or later.
    - CIM/WMI access permissions on local and remote systems.
    - WinRM enabled and accessible for remote queries.
    - Write permissions to the export directory when exporting.

.NOTES
    Author: ConnectTek
    Last Updated: 2025-08-09
#>

    [CmdletBinding()]
    param (
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [ValidateSet('CSV','JSON','XML','TXT','HTML')]
        [string]$ExportFormat,

        [string]$ExportPath
    )

    $scriptBlock = {
        try {
            $boards = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop
        } catch {
            Write-Warning "[$env:COMPUTERNAME] Failed to retrieve motherboard info: $($_.Exception.Message)"
            return
        }

        # Return one grouped object per computer
        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            Boards       = foreach ($b in $boards) {
                # Keep naming consistent with your style
                [pscustomobject]([ordered]@{
                    'Manufacturer' = $b.Manufacturer
                    'Product'      = $b.Product
                    'SerialNumber' = $b.SerialNumber
                    'Version'      = $b.Version
                    'PartNumber'   = $b.PartNumber
                })
            }
        }
    }

    # Gather results from all computers
    $results = foreach ($comp in $ComputerName) {
        try {
            if ($comp -eq $env:COMPUTERNAME) {
                & $scriptBlock
            } else {
                Invoke-Command -ComputerName $comp -ScriptBlock $scriptBlock -ErrorAction Stop
            }
        } catch {
            Write-Warning "Failed to retrieve motherboard info from '$comp': $($_.Exception.Message)"
        }
    }

    # ---- Console output: grouped per computer ----
    foreach ($entry in $results) {
        Write-Host "`nComputer: $($entry.ComputerName)" -ForegroundColor Cyan
        Write-Host ('-' * 40)
        foreach ($board in $entry.Boards) {
            foreach ($prop in $board.PSObject.Properties) {
                "{0,-14}: {1}" -f $prop.Name, $prop.Value
            }
            Write-Host ""
        }
    }

    # ---- Export (optional) ----
    if ($ExportFormat) {
        # Resolve/export folder
        $folder = if ($ExportPath) { $ExportPath } else { [System.IO.Path]::GetTempPath().TrimEnd('\') }

        if (-not (Test-Path $folder)) {
            $newDirParams = [ordered]@{
                Path     = $folder
                ItemType = 'Directory'
                Force    = $true
            }
            try {
                New-Item @newDirParams | Out-Null
            } catch {
                Write-Error "Failed to create export directory at '$folder': $($_.Exception.Message)"
                return
            }
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $ext       = $ExportFormat.ToLower()
        $filename  = "MotherboardInfo_$timestamp.$ext"
        $filePath  = Join-Path $folder $filename

        try {
            switch ($ExportFormat) {
                'CSV' {
                    # Flatten: one row per board with ComputerName attached
                    $flat = foreach ($entry in $results) {
                        foreach ($board in $entry.Boards) {
                            $row = [ordered]@{ ComputerName = $entry.ComputerName }
                            foreach ($p in $board.PSObject.Properties) { $row[$p.Name] = $p.Value }
                            [pscustomobject]$row
                        }
                    }
                    $csvParams = [ordered]@{
                        Path              = $filePath
                        NoTypeInformation = $true
                        Encoding          = 'UTF8'
                    }
                    $flat | Export-Csv @csvParams
                }
                'JSON' {
                    $jsonParams = [ordered]@{ Depth = 5 }
                    ($results | ConvertTo-Json @jsonParams) | Set-Content -Path $filePath -Encoding UTF8
                }
                'XML' {
                    $xmlParams = [ordered]@{ Path = $filePath }
                    $results | Export-Clixml @xmlParams
                }
                'TXT' {
                    # Pretty, grouped text
                    $text = foreach ($entry in $results) {
                        "Computer: $($entry.ComputerName)`r`n" + ('-' * 40) + "`r`n" +
                        (($entry.Boards | ForEach-Object { ($_ | Format-List | Out-String).TrimEnd() + "`r`n" }) -join "`r`n")
                    }
                    $setParams = [ordered]@{
                        Path     = $filePath
                        Encoding = 'UTF8'
                        Value    = ($text -join "`r`n")
                    }
                    Set-Content @setParams
                }
                'HTML' {
                    $html = ""
                    foreach ($entry in $results) {
                        $html += "<h2>Computer: $($entry.ComputerName)</h2><hr/>"
                        foreach ($board in $entry.Boards) {
                            $html += ($board | ConvertTo-Html -Fragment)
                            $html += "<br/>"
                        }
                    }
                    $htmlDoc = "<html><body>$html</body></html>"
                    $htmlParams = [ordered]@{
                        Path     = $filePath
                        Encoding = 'UTF8'
                        Value    = $htmlDoc
                    }
                    Set-Content @htmlParams
                }
            }

            Write-Host "`nExported file saved to:`n$($filePath)" -ForegroundColor Green
        } catch {
            Write-Error "Failed to export file to '$filePath': $($_.Exception.Message)"
        }
    }
}
