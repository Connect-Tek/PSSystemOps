function Get-DiskInfo {
<#
.SYNOPSIS
    Retrieves detailed disk information from local or remote Windows computers.

.DESCRIPTION
    Collects data from multiple sources:
    - Get-Disk for core disk properties.
    - Get-PhysicalDisk for physical attributes (media type, health, usage).
    - Win32_DiskDrive (via CIM) for model, serial number, and interface type.
    Matches and merges this data to provide a detailed list of each disk’s number, friendly name, model, serial number, 
    interface type, bus type, media type, health, operational status, boot/system flags, partition style, and size (GB).
    Results are grouped by computer and can optionally be exported to CSV, JSON, XML, TXT, or HTML formats.

.PARAMETER ComputerName
    One or more computer names to query.
    Defaults to the local computer if not specified.

.PARAMETER ExportFormat
    Optional export format for the results.
    Supported values: CSV, JSON, XML, TXT, HTML.

.PARAMETER ExportPath
    Optional directory path for saving the export file.
    If omitted, a temporary directory will be used.

.EXAMPLE
    Get-DiskInfo
    Displays detailed disk information for the local computer.

.EXAMPLE
    Get-DiskInfo -ComputerName "Server01","Server02"
    Retrieves disk information from multiple remote computers.

.EXAMPLE
    Get-DiskInfo -ExportFormat CSV -ExportPath "C:\Reports"
    Retrieves disk information from the local computer and exports it as a CSV file.

.EXAMPLE
    Get-DiskInfo -ComputerName "PC01" -ExportFormat HTML
    Retrieves disk info from PC01 and saves an HTML report in the temp directory.

.LIMITATIONS
    - Mapping between Get-Disk, Get-PhysicalDisk, and Win32_DiskDrive is best-effort and may not always match perfectly.
    - Some systems may not expose all properties (e.g., Serial Number, Media Type).
    - Remote execution requires network connectivity and WinRM configuration.
    - Export directory must be writable; the script attempts to create it if missing.

.REQUIREMENTS
    - PowerShell 5.1 or later.
    - Administrative privileges may be required to access full disk information.
    - WinRM enabled and accessible for remote execution.
    - CIM/WMI permissions on target systems.

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
            $disks = Get-Disk -ErrorAction Stop
        } catch {
            Write-Warning "[$env:COMPUTERNAME] Failed to retrieve Get-Disk: $($_.Exception.Message)"
            return
        }

        try {
            $physicalDisks = Get-PhysicalDisk -ErrorAction Stop
        } catch {
            Write-Warning "[$env:COMPUTERNAME] Get-PhysicalDisk failed: $($_.Exception.Message)"
            $physicalDisks = @()
        }

        try {
            $wmiDisks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop
        } catch {
            Write-Warning "[$env:COMPUTERNAME] Win32_DiskDrive query failed: $($_.Exception.Message)"
            $wmiDisks = @()
        }

        # Build one grouped object per computer, with a Disks array
        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            Disks        = foreach ($disk in $disks) {
                # Map to Win32_DiskDrive by Index -> Disk.Number
                $wmi = $wmiDisks | Where-Object { $_.Index -eq $disk.Number } | Select-Object -First 1
                # Best-effort map to PhysicalDisk (FriendlyName commonly aligns)
                $pd  = $physicalDisks | Where-Object { $_.FriendlyName -eq $disk.FriendlyName } | Select-Object -First 1

                [pscustomobject]([ordered]@{
                    'Number'             = $disk.Number
                    'Friendly Name'      = $disk.FriendlyName
                    'Model'              = $wmi.Model
                    'Serial Number'      = $wmi.SerialNumber
                    'Interface Type'     = $wmi.InterfaceType
                    'Bus Type'           = $disk.BusType
                    'Media Type'         = $pd.MediaType
                    'Can Pool'           = $pd.CanPool
                    'Usage'              = $pd.Usage
                    'Health Status'      = $disk.HealthStatus
                    'Operational Status' = ($disk.OperationalStatus -join ', ')
                    'Is Boot'            = $disk.IsBoot
                    'Is System'          = $disk.IsSystem
                    'Partition Style'    = $disk.PartitionStyle
                    'Size (GB)'          = [math]::Round($disk.Size / 1GB, 2)
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
            Write-Warning "Failed to collect disk data from '$comp': $($_.Exception.Message)"
        }
    }

    # Console output: grouped by computer
    foreach ($entry in $results) {
        Write-Host "`nComputer: $($entry.ComputerName)" -ForegroundColor Cyan
        Write-Host ('-' * 40)
        foreach ($d in $entry.Disks) {
            foreach ($p in $d.PSObject.Properties) {
                "{0,-20}: {1}" -f $p.Name, $p.Value
            }
            Write-Host ""
        }
    }

    # Export handling (optional)
    if ($ExportFormat) {

        # Resolve folder (default to %TEMP%)
        $folder = if ($ExportPath) { $ExportPath } else { [System.IO.Path]::GetTempPath().TrimEnd('\') }

        if (-not (Test-Path $folder)) {
            $newDirParams = [ordered]@{
                Path     = $folder
                ItemType = 'Directory'
                Force    = $true
            }
            try { New-Item @newDirParams | Out-Null } catch {
                Write-Error "Failed to create export directory at '$folder': $($_.Exception.Message)"
                return
            }
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $ext       = $ExportFormat.ToLower()
        $filename  = "DiskInfo_$timestamp.$ext"
        $filePath  = Join-Path $folder $filename

        try {
            switch ($ExportFormat) {
                'CSV' {
                    # Flatten: one row per disk with ComputerName column
                    $flat = foreach ($entry in $results) {
                        foreach ($d in $entry.Disks) {
                            $row = [ordered]@{ ComputerName = $entry.ComputerName }
                            foreach ($p in $d.PSObject.Properties) { $row[$p.Name] = $p.Value }
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
                    $text = foreach ($entry in $results) {
                        "Computer: $($entry.ComputerName)`r`n" + ('-' * 40) + "`r`n" +
                        (($entry.Disks | ForEach-Object { ($_ | Format-List | Out-String).TrimEnd() + "`r`n" }) -join "`r`n")
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
                        foreach ($d in $entry.Disks) {
                            $html += ($d | ConvertTo-Html -Fragment)
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
            Write-Error "Failed to export to '$filePath': $($_.Exception.Message)"
        }
    }
}

