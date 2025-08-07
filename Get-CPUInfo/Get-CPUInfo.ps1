function Get-CPUInfo {
<#
.SYNOPSIS
    Retrieves detailed CPU and system process information from local or remote computers.

.DESCRIPTION
    This function collects CPU information such as name, architecture, cores, cache size, and clock speed using WMI.
    It also gathers basic runtime system stats like number of running processes, total threads, and handles.
    Results can be optionally exported in a chosen format.

.PARAMETER ComputerName
    One or more computer names to retrieve CPU info from.
    Defaults to the local computer if not specified.

.PARAMETER ExportFormat
    Output format for saving the data. Supported values: CSV, JSON, XML, TXT, HTML.

.PARAMETER ExportPath
    Optional path to store the exported file. If not provided, a temporary directory is used.

.EXAMPLE
    Get-CPUInfo
    Retrieves CPU info from the local computer.

.EXAMPLE
    Get-CPUInfo -ComputerName "Server01","Server02"
    Gets CPU and process info from the specified servers.

.EXAMPLE
    Get-CPUInfo -ComputerName "Server01" -ExportFormat CSV -ExportPath "C:\Reports"
    Exports CPU info for Server01 as a CSV to C:\Reports.

.LIMITATIONS
    - Remote execution depends on proper WinRM configuration and connectivity.
    - If process statistics retrieval fails, values will show as "Unavailable".
    - Export folder must be writable; function will attempt to create it if missing.

.REQUIREMENTS
    - PowerShell 5.1 or later.
    - Administrator rights may be necessary on local or remote systems.
    - WinRM must be enabled and accessible for remote system access.

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
            $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
        }
        catch {
            Write-Warning "[$env:COMPUTERNAME] Failed to retrieve CPU info: $($_.Exception.Message)"
            return
        }

        # Get system-wide process stats
        try {
            $procList = Get-Process -ErrorAction Stop
            $processCount = $procList.Count
            $totalThreads = ($procList | ForEach-Object { $_.Threads.Count }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            $totalHandles = ($procList | Select-Object -ExpandProperty Handles) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        } catch {
            $processCount = "Unavailable"
            $totalThreads = "Unavailable"
            $totalHandles = "Unavailable"
        }

        # Convert architecture
        $arch = switch ($cpu.Architecture) {
            0 { 'x86' }
            1 { 'MIPS' }
            2 { 'Alpha' }
            3 { 'PowerPC' }
            5 { 'ARM' }
            6 { 'Itanium' }
            9 { 'x64' }
            default { 'Unknown' }
        }

        [pscustomobject]@{
            'ComputerName'         = $env:COMPUTERNAME
            'CPU_Name'             = $cpu.Name
            'Manufacturer'         = $cpu.Manufacturer
            'ProcessorID'          = $cpu.ProcessorId
            'Socket'               = $cpu.SocketDesignation
            'Architecture'         = $arch
            'Cores'                = $cpu.NumberOfCores
            'LogicalProcessors'    = $cpu.NumberOfLogicalProcessors
            'MaxClockSpeed (MHz)'  = $cpu.MaxClockSpeed
            'CurrentClockSpeed'    = $cpu.CurrentClockSpeed
            'L2Cache (KB)'         = $cpu.L2CacheSize
            'L3Cache (KB)'         = $cpu.L3CacheSize
            'Virtualization'       = $cpu.VirtualizationFirmwareEnabled
            'CPU Load (%)'         = $cpu.LoadPercentage
            'Running Processes'    = $processCount
            'Total Threads'        = $totalThreads
            'Total Handles'        = $totalHandles
            'Status'               = $cpu.Status
        }
    }

    $results = foreach ($comp in $ComputerName) {
        try {
            if ($comp -eq $env:COMPUTERNAME) {
                & $scriptBlock
            } else {
                Invoke-Command -ComputerName $comp -ScriptBlock $scriptBlock -ErrorAction Stop
            }
        }
        catch {
            Write-Warning "Failed to retrieve info from '$comp': $($_.Exception.Message)"
        }
    }

    $results

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
        $filename = "CPUInfo_$timestamp.$ext"
        $filePath = Join-Path $folder $filename

        try {
            switch ($ExportFormat) {
                'CSV'  { $results | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 }
                'JSON' { $results | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding UTF8 }
                'XML'  { $results | Export-Clixml -Path $filePath }
                'TXT'  { $results | Out-String | Set-Content -Path $filePath -Encoding UTF8 }
                'HTML' { $results | ConvertTo-Html | Set-Content -Path $filePath -Encoding UTF8 }
            }

            Write-Host "`nExported file saved to:`n$($filePath)" -ForegroundColor Cyan
        }
        catch {
            Write-Error "Failed to export file to '$filePath': $($_.Exception.Message)"
        }
    }
}
