function Get-OSInfo {
<#
.SYNOPSIS
    Retrieves Windows operating system details from local or remote computers.

.DESCRIPTION
    Uses WMI/CIM (Win32_OperatingSystem) along with registry queries to gather comprehensive OS details, 
    including version, build, architecture, installation date, last boot time, and product type.
    Results are grouped by computer for console display and can optionally be exported in CSV, JSON, XML, TXT, or HTML formats.

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
    Get-OSInfo
    Displays OS details for the local computer.

.EXAMPLE
    Get-OSInfo -ComputerName "Server01","Server02"
    Retrieves OS information from multiple remote computers.

.EXAMPLE
    Get-OSInfo -ExportFormat CSV -ExportPath "C:\Reports"
    Retrieves OS information from the local computer and exports it as a CSV file to the specified path.

.EXAMPLE
    Get-OSInfo -ComputerName "PC01" -ExportFormat HTML
    Retrieves OS info from PC01 and saves an HTML report to the temporary folder.

.LIMITATIONS
    - Some registry values (e.g., DisplayVersion, LCUVer) may be unavailable depending on Windows version.
    - Remote execution requires network connectivity and WinRM configuration.
    - Export path must be writable; the script attempts to create the folder if it does not exist.

.REQUIREMENTS
    - PowerShell 5.1 or later.
    - CIM/WMI permissions on local and remote systems.
    - WinRM enabled and accessible for remote systems.
    - Appropriate registry read permissions to retrieve extended version details.

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
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        } catch {
            Write-Warning "[$env:COMPUTERNAME] Failed to retrieve OS info: $($_.Exception.Message)"
            return
        }

        $regValues = $null
        try {
            $regValues = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
                -Name DisplayVersion, InstallationType, ReleaseId, EditionID, LCUVer, ProductId -ErrorAction Stop
        } catch {
            Write-Warning "[$env:COMPUTERNAME] Failed to access registry info: $($_.Exception.Message)"
        }

        # Build a grouped object per computer with nested OS fields
        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            OS           = [pscustomobject]([ordered]@{
                'OS Name'                   = ($os.Caption -replace '^Microsoft\s+', '').Trim()
                'Display Version'           = $regValues.DisplayVersion
                'Build Number'              = $os.BuildNumber
                'Cumulative Update Version' = $regValues.LCUVer
                'Architecture'              = $os.OSArchitecture
                'Install Date'              = $os.InstallDate
                'Last BootUp Time'          = $os.LastBootUpTime
                'Product Id'                = $regValues.ProductId
                'Registered User'           = $os.RegisteredUser
                'Organization'              = $os.Organization
                'Boot Device'               = $os.BootDevice
                'System Directory'          = $os.SystemDirectory
                'Windows Directory'         = $os.WindowsDirectory
                'Product Type'              = switch ($os.ProductType) {
                                                 1 { 'Workstation' }
                                                 2 { 'Domain Controller' }
                                                 3 { 'Server' }
                                                 default { "Unknown ($($os.ProductType))" }
                                             }
                'OS Language'               = $os.OSLanguage
                'Locale'                    = $os.Locale
            })
        }
    }

    # Collect results
    $results = foreach ($comp in $ComputerName) {
        try {
            if ($comp -eq $env:COMPUTERNAME) {
                & $scriptBlock
            } else {
                Invoke-Command -ComputerName $comp -ScriptBlock $scriptBlock -ErrorAction Stop
            }
        } catch {
            Write-Warning "Failed to retrieve OS info from '$comp': $($_.Exception.Message)"
        }
    }

    # Console output: grouped by computer
    foreach ($entry in $results) {
        Write-Host "`nComputer: $($entry.ComputerName)" -ForegroundColor Cyan
        Write-Host ('-' * 40)
        $entry.OS | Format-List
    }

    # Export handling
    if ($ExportFormat) {
        $folder = if ($ExportPath) { $ExportPath } else { [System.IO.Path]::GetTempPath().TrimEnd('\') }

        if (-not (Test-Path $folder)) {
            $mkdirParams = [ordered]@{
                Path     = $folder
                ItemType = 'Directory'
                Force    = $true
            }
            try {
                New-Item @mkdirParams | Out-Null
            } catch {
                Write-Error "Failed to create export directory at '$folder': $($_.Exception.Message)"
                return
            }
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $ext       = $ExportFormat.ToLower()
        $filename  = "OSInfo_$timestamp.$ext"
        $filePath  = Join-Path $folder $filename

        try {
            switch ($ExportFormat) {
                'CSV' {
                    # Flatten per computer: ComputerName + OS properties as columns
                    $flat = foreach ($entry in $results) {
                        $row = [ordered]@{ ComputerName = $entry.ComputerName }
                        foreach ($p in $entry.OS.PSObject.Properties) {
                            # Avoid duplicate Computer Name column if present
                            if ($p.Name -ne 'Computer Name') {
                                $row[$p.Name] = $p.Value
                            }
                        }
                        [pscustomobject]$row
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
                        (($entry.OS | Format-List | Out-String).TrimEnd() + "`r`n")
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
                        $html += ($entry.OS | ConvertTo-Html -Fragment)
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
