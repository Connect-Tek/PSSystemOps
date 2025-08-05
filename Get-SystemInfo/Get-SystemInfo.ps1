function Get-SystemInfo {
<#
.SYNOPSIS
Retrieves system information from one or more computers.

.DESCRIPTION
This function collects hardware and operating system details such as RAM, CPU, serial number, and uptime.
It can run against local or remote computers and export the results to a file in CSV, JSON, XML, or TXT format.

If -ExportFormat is specified, the results are saved to a single file.
If -ExportPath is not provided, the file is saved in the system TEMP folder.
If -ExportPath is provided, the file is saved in that location.
The export filename is automatically generated with a timestamp.

.PARAMETER ComputerName
Specifies one or more computer names to query. Defaults to the local computer if not specified.

.PARAMETER ExportFormat
Optional. If specified, the function exports results to a file.
Supported values: CSV, JSON, XML, TXT.

.PARAMETER ExportPath
Optional. If provided, sets the folder where the export file is saved.
If not provided, the file is saved in the system's TEMP folder.

.EXAMPLE
Get-SystemInfo

Retrieves system info from the local computer and displays the result in the console.

.EXAMPLE
Get-SystemInfo -ComputerName "SERVER1","SERVER2"

Retrieves system info from SERVER1 and SERVER2 and displays the result in the console.

.EXAMPLE
Get-SystemInfo -ComputerName "SERVER1","SERVER2" -ExportFormat CSV

Retrieves system info from SERVER1 and SERVER2 and exports it to a CSV file in the TEMP folder.

.EXAMPLE
Get-SystemInfo -ComputerName "SERVER1" -ExportFormat JSON -ExportPath "C:\Reports"

Retrieves system info from SERVER1 and saves the result as a JSON file in the C:\Reports folder.

.NOTES
Author  : ConnectTek
Version : 1.0
Date    : 2025-08-05
#>

    [CmdletBinding()]
    param (
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [ValidateSet('CSV', 'JSON', 'XML', 'TXT')]
        [string]$ExportFormat,
        [string]$ExportPath
    )

    $scriptBlock = {
        param($ComputerName)

        try {
            $sysDetails = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        } catch {
            Write-Warning "Failed to retrieve system details for '$ComputerName'"
            Write-Warning $_.Exception.Message
            Write-Warning $_.InvocationInfo.PositionMessage
        }

        try {
            $serialNumber = (Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber
        } catch {
            Write-Warning "Failed retrieving serial number for '$ComputerName'"
            Write-Warning $_.Exception.Message
            Write-Warning $_.InvocationInfo.PositionMessage
        }

        try {
            $ramTotal = [math]::Round(((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB))
        } catch {
            Write-Warning "Failed retrieving total ram for '$ComputerName'"
            Write-Warning $_.Exception.Message
            Write-Warning $_.InvocationInfo.PositionMessage
        }

        try {
            $cpuSpecs = Get-CimInstance Win32_Processor -ErrorAction Stop
        } catch {
            Write-Warning "Failed retrieving CPU specs for '$ComputerName'"
            Write-Warning $_.Exception.Message
            Write-Warning $_.InvocationInfo.PositionMessage
        }

        try {
            $osDetails = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        } catch {
            Write-Warning "Failed retrieving OS details for '$ComputerName'"
            Write-Warning $_.Exception.Message
            Write-Warning $_.InvocationInfo.PositionMessage
        }

        $uptimeSpan = (Get-Date) - $osDetails.LastBootUpTime
        $uptimeFormatted = "{0} days, {1} hours, {2} minutes" -f $uptimeSpan.Days, $uptimeSpan.Hours, $uptimeSpan.Minutes

        [PSCustomObject]@{
            'Computer Name'        = $sysDetails.Name
            'Domain'               = $sysDetails.Domain
            'Serial Number'        = $serialNumber
            'Manufacturer'         = $sysDetails.Manufacturer
            'Model'                = $sysDetails.Model
            'System Type'          = $sysDetails.SystemType
            'Installed RAM'        = "$ramTotal GB"
            'Processesor'          = $cpuSpecs.Name
            'Number of Cores'      = $cpuSpecs.NumberOfCores
            'Logical Processors'   = $cpuSpecs.NumberOfLogicalProcessors
            'OS Name'              = $osDetails.Caption
            'OS Version'           = $osDetails.Version
            'Last Boot'            = ($osDetails.LastBootUpTime).ToLocalTime()
            'Uptime'               = $uptimeFormatted
        }
    }

    # Collect results
    $results = foreach ($comp in $ComputerName) {
        Invoke-Command -ComputerName $comp -ScriptBlock $scriptBlock -ArgumentList $comp
    }

    # Output the object(s) to console first
    $results

    # Then handle export (if requested)
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
        $ext = switch ($ExportFormat) {
            'CSV'  { 'csv' }
            'JSON' { 'json' }
            'XML'  { 'xml' }
            'TXT'  { 'txt' }
        }

        $filename = "SystemInfo_$timestamp.$ext"
        $filePath = Join-Path $folder $filename

        try {
            switch ($ExportFormat) {
                'CSV'  { $results | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 }
                'JSON' { $results | ConvertTo-Json -Depth 4 | Set-Content -Path $filePath -Encoding UTF8 }
                'XML'  { $results | Export-Clixml -Path $filePath }
                'TXT'  { $results | Out-String | Set-Content -Path $filePath -Encoding UTF8 }
            }

            
            Write-Host "`nExported file saved to:`n$($filePath)" -ForegroundColor Cyan
        } catch {
            Write-Error "Failed to export file to '$filePath': $($_.Exception.Message)"
        }
    }
}

Get-SystemInfo -ComputerName "TEK-DC01","TEK-SRV" -ExportFormat XML 
