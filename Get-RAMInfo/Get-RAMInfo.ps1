function Get-RAMInfo {
<#
.SYNOPSIS
    Retrieves RAM (physical memory) module details from local or remote computers.

.DESCRIPTION
    Uses WMI/CIM (Win32_PhysicalMemory) to list installed RAM modules per computer.
    For each module, it returns bank label, capacity (GB), speed (MHz), data width, manufacturer, part number, and serial number.
    Results are printed grouped by computer and can optionally be exported to CSV, JSON, XML, TXT, or HTML.

.PARAMETER ComputerName
    One or more computer names to query.
    Defaults to the local computer if not specified.

.PARAMETER ExportFormat
    Optional export format. Supported values: CSV, JSON, XML, TXT, HTML.

.PARAMETER ExportPath
    Optional directory to save the exported file. If omitted, a temp directory is used.

.EXAMPLE
    Get-RAMInfo
    Shows RAM module details for the local computer.

.EXAMPLE
    Get-RAMInfo -ComputerName "Server01","Server02"
    Retrieves RAM info from multiple remote computers.

.EXAMPLE
    Get-RAMInfo -ExportFormat CSV -ExportPath "C:\Reports"
    Retrieves local RAM info and exports a flattened per-module CSV to C:\Reports.

.EXAMPLE
    Get-RAMInfo -ComputerName "PC01" -ExportFormat HTML
    Retrieves RAM info from PC01 and saves an HTML report to the temp folder.

.LIMITATIONS
    - Some systems may not expose all properties (e.g., Part Number or Serial Number can be blank).
    - Capacity and speed values depend on hardware/firmware reporting accuracy.
    - Remote queries require connectivity and permissions; failures are logged per computer.

.REQUIREMENTS
    - PowerShell 5.1 or later.
    - CIM/WMI access permissions on target machines.
    - WinRM enabled and reachable for remote computers.
    - Write access to the export path (if exporting).

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
            $modules = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop
        } catch {
            Write-Warning "[$env:COMPUTERNAME] Failed to retrieve RAM info: $($_.Exception.Message)"
            return
        }

        # Grouped object: one per computer, with a Modules array
        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            Modules      = foreach ($m in $modules) {
                [pscustomobject]([ordered]@{
                    'Bank Label'       = $m.BankLabel
                    'Capacity (GB)'    = [math]::Round(($m.Capacity / 1GB), 2)
                    'Speed (MHz)'      = $m.Speed
                    'DataWidth (bits)' = $m.DataWidth
                    'Manufacturer'     = $m.Manufacturer
                    'Part Number'      = ($m.PartNumber).Trim()
                    'Serial Number'    = $m.SerialNumber
                })
            }
        }
    }

    # Collect results from all computers
    $results = foreach ($comp in $ComputerName) {
        try {
            if ($comp -eq $env:COMPUTERNAME) {
                & $scriptBlock
            } else {
                Invoke-Command -ComputerName $comp -ScriptBlock $scriptBlock -ErrorAction Stop
            }
        } catch {
            Write-Warning "Failed to retrieve RAM info from '$comp': $($_.Exception.Message)"
        }
    }

    # Console output: grouped by computer (FIXED: enumerate properties correctly)
    foreach ($entry in $results) {
        Write-Host "`nComputer: $($entry.ComputerName)" -ForegroundColor Cyan
        Write-Host ('-' * 40)
        foreach ($mod in $entry.Modules) {
            foreach ($prop in $mod.PSObject.Properties) {
                "{0,-18}: {1}" -f $prop.Name, $prop.Value
            }
            Write-Host ""
        }
    }

    # Export handling (optional)
    if ($ExportFormat) {
        # Resolve folder target (temp if none)
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
        $filename  = "RAMInfo_$timestamp.$ext"
        $filePath  = Join-Path $folder $filename

        try {
            switch ($ExportFormat) {
                'CSV' {
                    # Flatten: one row per module, include ComputerName
                    $flat = foreach ($entry in $results) {
                        foreach ($mod in $entry.Modules) {
                            $row = [ordered]@{ ComputerName = $entry.ComputerName }
                            foreach ($p in $mod.PSObject.Properties) { $row[$p.Name] = $p.Value }
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
                        (($entry.Modules | ForEach-Object { ($_ | Format-List | Out-String).TrimEnd() + "`r`n" }) -join "`r`n")
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
                        foreach ($mod in $entry.Modules) {
                            $html += ($mod | ConvertTo-Html -Fragment)
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
