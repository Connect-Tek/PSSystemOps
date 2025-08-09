function Get-InstalledSoftwareInfo {
<#
.SYNOPSIS
    Retrieves a list of installed software from local or remote Windows computers.

.DESCRIPTION
    Queries the Windows registry to collect installed application details from both 32-bit and 64-bit registry locations, 
    as well as the current user’s installed software. Returns application name, version, vendor, size, 
    installation date, location, source, and shortcut path.
    You can filter results by a keyword and optionally export to CSV, JSON, XML, TXT, or HTML.

.PARAMETER ComputerName
    One or more computer names to query.
    Defaults to the local computer if not specified.

.PARAMETER SoftwareFilter
    Optional keyword filter to return only software with names matching the filter string (case-insensitive, partial match).

.PARAMETER ExportFormat
    Optional export format. Supported values: CSV, JSON, XML, TXT, HTML.

.PARAMETER ExportPath
    Optional path for saving exported data. Defaults to the system temp directory if omitted.

.EXAMPLE
    Get-InstalledSoftwareInfo
    Displays all installed software for the local computer.

.EXAMPLE
    Get-InstalledSoftwareInfo -SoftwareFilter "Office"
    Shows only installed software with "Office" in the name for the local computer.

.EXAMPLE
    Get-InstalledSoftwareInfo -ComputerName "Server01","Server02"
    Retrieves installed software lists from multiple remote computers.

.EXAMPLE
    Get-InstalledSoftwareInfo -ComputerName "PC01" -SoftwareFilter "Adobe" -ExportFormat CSV -ExportPath "C:\Reports"
    Retrieves Adobe-related software from PC01 and exports it as a CSV file to the specified folder.

.LIMITATIONS
    - Relies on registry data; may not include portable apps or software installed without registry entries.
    - Some applications may have incomplete or missing fields (e.g., Estimated Size, Install Date).
    - Remote execution requires WinRM to be enabled and accessible on target computers.
    - Registry read permissions are required for all queried hives.

.REQUIREMENTS
    - PowerShell 5.1 or later.
    - Registry access permissions on local/remote systems.
    - WinRM enabled and accessible for remote execution.
    - Write permissions for the export directory if exporting data.

.NOTES
    Author: ConnectTek
    Last Updated: 2025-08-09
#>

    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [string]$SoftwareFilter,

        [Parameter(Mandatory = $false)]
        [ValidateSet('CSV','JSON','XML','TXT','HTML')]
        [string]$ExportFormat,

        [Parameter(Mandatory = $false)]
        [string]$ExportPath
    )

    # ScriptBlock: returns one grouped object per computer { ComputerName; Software = [ ... ] }
    $scriptBlock = {
        param ($SoftwareFilter)

        try {
            $paths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )

            $raw = foreach ($p in $paths) {
                try { Get-ItemProperty -Path $p -ErrorAction Stop } catch { }
            }

            $filtered = $raw |
                Where-Object {
                    $_.DisplayName -and (
                        -not $SoftwareFilter -or $_.DisplayName -like "*$SoftwareFilter*"
                    )
                } |
                ForEach-Object {
                    [pscustomobject]([ordered]@{
                        'Name'             = $_.DisplayName
                        'Version'          = $_.DisplayVersion
                        'Vendor'           = $_.Publisher
                        'Size (MB)'        = if ($_.EstimatedSize -as [int]) { [math]::Round($_.EstimatedSize / 1024, 2) } else { $null }
                        'Install Date'     = if ($_.InstallDate -as [int]) {
                                                try { [datetime]::ParseExact($_.InstallDate, 'yyyyMMdd', $null).ToString('yyyy-MM-dd') } catch { $null }
                                             } else { $null }
                        'Install Location' = $_.InstallLocation
                        'Install Source'   = $_.InstallSource
                        'ShortCut Path'    = $_.DisplayIcon
                    })
                } |
                Sort-Object Name -Unique

            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                Software     = $filtered
            }
        }
        catch {
            Write-Warning "[$env:COMPUTERNAME] Error retrieving software info: $($_.Exception.Message)"
        }
    }

    # Gather results for all computers
    $results = foreach ($comp in $ComputerName) {
        try {
            if ($comp -eq $env:COMPUTERNAME) {
                & $scriptBlock $SoftwareFilter
            } else {
                Invoke-Command -ComputerName $comp -ScriptBlock $scriptBlock -ArgumentList $SoftwareFilter -ErrorAction Stop
            }
        } catch {
            Write-Warning "Failed to retrieve software from '$comp': $($_.Exception.Message)"
        }
    }

    # Console output: grouped by computer
    foreach ($entry in $results) {
        Write-Host "`nComputer: $($entry.ComputerName)" -ForegroundColor Cyan
        Write-Host ('-' * 40)
        if ($entry.Software -and $entry.Software.Count -gt 0) {
            $entry.Software | Select-Object 'Name','Version','Vendor','Size (MB)','Install Date','Install Location','Install Source','ShortCut Path' |
                Format-Table -AutoSize
        } else {
            Write-Host "(No results)" -ForegroundColor DarkGray
        }
    }

    # Export (optional)
    if ($ExportFormat) {
        # If no path: use temp folder
        $folder = if ($ExportPath) { $ExportPath } else { [System.IO.Path]::GetTempPath().TrimEnd('\') }

        # Ensure folder exists
        if (-not (Test-Path $folder)) {
            $mkdirParams = [ordered]@{ Path = $folder; ItemType = 'Directory'; Force = $true }
            try { New-Item @mkdirParams | Out-Null } catch {
                Write-Error "Failed to create export directory at '$folder': $($_.Exception.Message)"
                return
            }
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $ext       = $ExportFormat.ToLower()
        $filename  = "InstalledSoftwareInfo_$timestamp.$ext"
        $filePath  = Join-Path $folder $filename

        try {
            switch ($ExportFormat) {
                'CSV' {
                    # Flatten: one row per app, include ComputerName column
                    $flat = foreach ($entry in $results) {
                        foreach ($app in $entry.Software) {
                            $row = [ordered]@{ ComputerName = $entry.ComputerName }
                            foreach ($p in $app.PSObject.Properties) { $row[$p.Name] = $p.Value }
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
                    # Nested per computer with Software array
                    $jsonParams = [ordered]@{ Depth = 5 }
                    ($results | ConvertTo-Json @jsonParams) | Set-Content -Path $filePath -Encoding UTF8
                }
                'XML' {
                    $xmlParams = [ordered]@{ Path = $filePath }
                    $results | Export-Clixml @xmlParams
                }
                'TXT' {
                    # Readable, grouped text
                    $text = foreach ($entry in $results) {
                        "Computer: $($entry.ComputerName)`r`n" + ('-' * 40) + "`r`n" +
                        (($entry.Software | Format-Table | Out-String).TrimEnd() + "`r`n")
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
                        if ($entry.Software -and $entry.Software.Count -gt 0) {
                            $html += ($entry.Software |
                                Select-Object 'Name','Version','Vendor','Size (MB)','Install Date','Install Location','Install Source','ShortCut Path' |
                                ConvertTo-Html -Fragment)
                        } else {
                            $html += "<p><em>(No results)</em></p>"
                        }
                        $html += "<br/>"
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

