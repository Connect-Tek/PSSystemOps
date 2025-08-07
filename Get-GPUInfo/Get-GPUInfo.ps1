function Get-GPUInfo {
<#
.SYNOPSIS
    Retrieves GPU (graphics card) information from local or remote computers.

.DESCRIPTION
    This function uses WMI to gather detailed information about each GPU (video controller) on the target system(s).
    It returns driver details, video processor name, adapter RAM, current resolution, refresh rate, and other properties.
    Results can be optionally exported in multiple formats for reporting.

.PARAMETER ComputerName
    One or more computer names to query.
    Defaults to the local computer if not specified.

.PARAMETER ExportFormat
    Format to export the results. Supported values: CSV, JSON, XML, TXT, HTML.

.PARAMETER ExportPath
    Optional directory to store the export file. A temp directory is used if not provided.

.EXAMPLE
    Get-GPUInfo
    Retrieves GPU info from the local machine and outputs to console.

.EXAMPLE
    Get-GPUInfo -ComputerName "Server01","Server02"
    Retrieves GPU info from multiple remote computers.

.EXAMPLE
    Get-GPUInfo -ComputerName "Server01" -ExportFormat CSV -ExportPath "C:\Reports"
    Retrieves GPU info and exports it as CSV to the specified directory.

.LIMITATIONS
    - Adapter RAM may show as null if not reported by the system.
    - Remote retrieval requires WinRM to be enabled and accessible on the target machines.
    - HTML export is basic and intended for simple viewing only.

.REQUIREMENTS
    - PowerShell 5.1 or later.
    - Appropriate permissions for WMI access.
    - Remote systems must allow PowerShell remoting (WinRM enabled).

.NOTES
    Author: ConnectTek  
    Last Updated: 2025-08-07
#>
    [CmdletBinding()]
    param (
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [ValidateSet('CSV', 'JSON', 'XML', 'TXT', 'HTML')]
        [string]$ExportFormat,

        [string]$ExportPath
    )

    $scriptBlock = {
        try {
            $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop
        } catch {
            Write-Warning "[$env:COMPUTERNAME] Failed to retrieve GPU info: $($_.Exception.Message)"
            return
        }

        return @{
            ComputerName = $env:COMPUTERNAME
            GPUs = $gpus | ForEach-Object {
                [ordered]@{
                    Name                      = $_.Name
                    'Driver Version'          = $_.DriverVersion
                    'Driver Date'             = $_.DriverDate
                    'Video Processor'         = $_.VideoProcessor
                    'Adapter RAM (MB)'        = if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1MB, 0) } else { $null }
                    'Video Mode Description'  = $_.VideoModeDescription
                    'Current Refresh Rate'    = $_.CurrentRefreshRate
                    'Horizontal Resolution'   = $_.CurrentHorizontalResolution
                    'Vertical Resolution'     = $_.CurrentVerticalResolution
                    'PNP DeviceID'            = $_.PNPDeviceID
                    'Installed Display Drivers' = $_.InstalledDisplayDrivers
                    Status                    = $_.Status
                }
            }
        }
    }

    $results = foreach ($comp in $ComputerName) {
        try {
            if ($comp -eq $env:COMPUTERNAME) {
                & $scriptBlock
            } else {
                Invoke-Command -ComputerName $comp -ScriptBlock $scriptBlock -ErrorAction Stop
            }
        } catch {
            Write-Warning "Failed to retrieve GPU info from '$comp': $($_.Exception.Message)"
        }
    }

    # --- Console Output (grouped per computer) ---
    foreach ($entry in $results) {
        Write-Host "`nComputer: $($entry.ComputerName)" -ForegroundColor Cyan
        Write-Host ('-' * 40)
        foreach ($gpu in $entry.GPUs) {
            $gpu.GetEnumerator() | ForEach-Object { "{0,-25}: {1}" -f $_.Key, $_.Value }
            Write-Host ""
        }
    }

    # --- Export Logic ---
    if ($ExportFormat) {
        $folder = if ($ExportPath) { $ExportPath } else { [System.IO.Path]::GetTempPath().TrimEnd('\') }

        if (-not (Test-Path $folder)) {
            try {
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
            } catch {
                Write-Error "Failed to create export directory at '$folder': $($_.Exception.Message)"
                return
            }
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $ext = $ExportFormat.ToLower()
        $filename = "GPUInfo_$timestamp.$ext"
        $filePath = Join-Path $folder $filename

        try {
            switch ($ExportFormat) {
                'CSV'  {
                    $results | ForEach-Object {
                        $comp = $_.ComputerName
                        $_.GPUs | ForEach-Object {
                            $_ | Add-Member -NotePropertyName ComputerName -NotePropertyValue $comp -Force
                            $_
                        }
                    } | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8
                }
                'JSON' {
                    $results | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding UTF8
                }
                'XML' {
                    $results | Export-Clixml -Path $filePath
                }
                'TXT' {
                    $results | ForEach-Object {
                        "Computer: $($_.ComputerName)`n" + ('-' * 40) + "`n" +
                        ($_.GPUs | ForEach-Object {
                            ($_ | Format-List | Out-String) + "`n"
                        }) -join "`n"
                    } | Set-Content -Path $filePath -Encoding UTF8
                }
                'HTML' {
                    $html = ""
                    foreach ($entry in $results) {
                        $html += "<h2>Computer: $($entry.ComputerName)</h2><hr/>"
                        foreach ($gpu in $entry.GPUs) {
                            $html += ($gpu | ConvertTo-Html -Fragment)
                            $html += "<br/>"
                        }
                    }
                    $html = "<html><body>$html</body></html>"
                    Set-Content -Path $filePath -Value $html -Encoding UTF8
                }
            }

            Write-Host "`nExported file saved to:`n$($filePath)" -ForegroundColor Green
        } catch {
            Write-Error "Failed to export file to '$filePath': $($_.Exception.Message)"
        }
    }
}

