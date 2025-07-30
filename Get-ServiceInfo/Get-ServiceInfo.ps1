function Get-ServiceInfo {
<#
.SYNOPSIS
Retrieves detailed information about services on one or more Windows computers.

.DESCRIPTION
This function queries local or remote systems using CIM to gather service information.
It supports filtering by service name, status, and start type, and can optionally include
dependency details. The results can also be exported to CSV, JSON, XML, or TXT formats.

.PARAMETER Name
Filters services by exact name. Defaults to '*', which includes all services.

.PARAMETER Status
Filters services by current state. Valid options: Running, Stopped, Paused, or All (default).

.PARAMETER StartType
Filters services by start type. Valid options: Automatic, Manual, Disabled, or All (default).

.PARAMETER ShowDependencies
If specified, includes dependency information: which services this one depends on and
which services depend on it. Works locally and remotely via Invoke-Command.

.PARAMETER ExportFormat
Optional. Exports the output to a file in the specified format.
Supported values: CSV, JSON, XML, TXT.

.PARAMETER ExportPath
Optional. Sets the directory to save the export file.
If not provided, defaults to the system TEMP folder.

.PARAMETER ComputerName
Specifies one or more computers to query.
Defaults to the local machine if not specified.

.EXAMPLE
Get-ServiceInfo

Retrieves all services from the local machine.

.EXAMPLE
Get-ServiceInfo -Name Spooler -ShowDependencies

Gets the Spooler service and its dependencies from the local computer.

.EXAMPLE
Get-ServiceInfo -ComputerName "SERVER1","SERVER2" -Status Running -ExportFormat CSV

Gets all running services from SERVER1 and SERVER2, and exports each result to CSV.

.NOTES
Author  : ConnectTek  
Version : 1.1  
Date    : 2025-07-30
#>


    [CmdletBinding()]
    #---------------------- Defining Parameters ----------------------#
    param(
        # Service name filter, supports wildcards (e.g. spooler or *sql*), defaults to '*'
        [string]$Name = '*',

        # Filter services by their current status. Defaults to 'All'
        [ValidateSet('Running', 'Stopped', 'Paused', 'All')]
        [string]$Status = 'All',

        # Filter services by how they start (Automatic, Manual, Disabled). Defaults to 'All'
        [ValidateSet('Automatic', 'Manual', 'Disabled', 'All')]
        [string]$StartType = 'All',

        # If used, adds service dependency information to output
        [switch]$ShowDependencies,

        # Format to export the service list in (CSV, JSON, XML, TXT)
        [ValidateSet('CSV', 'JSON', 'XML', 'TXT')]
        [string]$ExportFormat,

        # Optional file path to save the export file
        [string]$ExportPath,

        # Target computer to check services on. Can specify multiple
        [string[]]$ComputerName = $env:COMPUTERNAME
    )

    foreach ($comp in $ComputerName) {

        #---------------------- Get service data from local or remote ----------------------#
        # Get services using CIM on local or remote machine
        try {
            if ($comp -eq $env:COMPUTERNAME) {
                # Local machine: use CIM to get service information
                $ServiceList = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop
            }
            else {
                # Remote machine: use CIM with -ComputerName to query remote services
                $ServiceList = Get-CimInstance -ClassName Win32_Service -ComputerName $comp -ErrorAction Stop
            }
        }
        catch {
            # Show error message if we couldn't get the service list
            Write-Error "Failed to retrieve services from '$comp': $($_.Exception.Message)"
            continue
        }

        #---------------------- Filter by Service Name ----------------------#
        # If user supplied a name filter, apply it to service name or display name
        if ($Name -ne '*') {
            $ServiceList = $ServiceList | Where-Object {
                $_.Name -like "*$Name*" -or $_.DisplayName -like "*$Name*"
            }

            # If no matching services found, warn and skip to next computer
            if (-not $ServiceList) {
                Write-Warning "No services found matching the name or display name: '$Name' on '$comp'"
                continue
            }
        }

        #---------------------- Filter by Service Status ----------------------#
        # Match services where current state equals selected status
        if ($Status -ne 'All') {
            $ServiceList = $ServiceList | Where-Object { $_.State -ieq $Status }
        }

        #---------------------- Filter by Service Start Type ----------------------#
        # Match services by their start mode (Automatic, Manual, Disabled)
        if ($StartType -ne 'All') {
            $ServiceList = $ServiceList | Where-Object { $_.StartMode -ieq $StartType }
        }

        #---------------------- Get Remote Dependencies if needed ----------------------#
        # If dependencies are requested and the target is remote, collect them separately
        $RemoteDeps = @{}
        if ($ShowDependencies -and $comp -ne $env:COMPUTERNAME) {
            try {
                # Run command remotely to gather dependent and required services
                $RemoteDeps = Invoke-Command -ComputerName $comp -ScriptBlock {
                    Get-Service | ForEach-Object {
                        [PSCustomObject]@{
                            Name       = $_.Name
                            DependsOn  = ($_.ServicesDependedOn   | ForEach-Object { $_.DisplayName }) -join ', '
                            UsedBy     = ($_.DependentServices    | ForEach-Object { $_.DisplayName }) -join ', '
                        }
                    }
                } -ErrorAction Stop
            }
            catch {
                # If remote dependency check fails, skip it
                $RemoteDeps = $null
            }
        }

        #---------------------- Print source computer header ----------------------#
        # Display which computer the services were retrieved from
        if ($ServiceList.Count -gt 0) {
            Write-Host "`nServices retrieved from: $comp`n" -ForegroundColor Cyan
        }

        #---------------------- Loop and create output list ----------------------#
        # Prepare list of output objects to show/export later
        $ResultList = @()

        foreach ($Service in $ServiceList) {
            # Build a result row with name, display name, status and start type
            $output = [ordered]@{
                'Name'         = $Service.Name
                'Display Name' = $Service.DisplayName
                'Status'       = $Service.State
                'Start Type'   = $Service.StartMode
            }

            # If dependencies are requested, try to gather them
            if ($ShowDependencies) {
                if ($comp -eq $env:COMPUTERNAME) {
                    # For local machine, use Get-Service to get dependency info
                    try {
                        $svc = Get-Service -Name $Service.Name -ErrorAction Stop
                        $dependsOn = $svc.ServicesDependedOn | Select-Object -ExpandProperty DisplayName
                        $usedBy    = $svc.DependentServices  | Select-Object -ExpandProperty DisplayName

                        $output['Depends On'] = if ($dependsOn) { $dependsOn -join ', ' } else { 'None' }
                        $output['Used By']    = if ($usedBy)    { $usedBy    -join ', ' } else { 'None' }
                    }
                    catch {
                        # In case Get-Service fails, mark as Unknown
                        $output['Depends On'] = 'Unknown'
                        $output['Used By']    = 'Unknown'
                    }
                }
                else {
                    # For remote computers, use previously fetched remote dependency data
                    if ($RemoteDeps) {
                        $match = $RemoteDeps | Where-Object { $_.Name -eq $Service.Name }
                        $output['Depends On'] = if ($match -and $match.DependsOn) { $match.DependsOn } else { 'None' }
                        $output['Used By']    = if ($match -and $match.UsedBy)    { $match.UsedBy } else { 'None' }
                    }
                    else {
                        # If no dependency data, label as unavailable
                        $output['Depends On'] = 'Unavailable'
                        $output['Used By']    = 'Unavailable'
                    }
                }
            }

            # Add this row to the final result list
            $ResultList += [PSCustomObject]$output
        }

        #---------------------- Export to file if requested ----------------------#
        # Only run export logic if user supplied ExportFormat or ExportPath
        $filePath = $null
        if (($ExportFormat -or $ExportPath) -and $ResultList.Count -gt 0) {
            # Use custom export path if provided, else use TEMP folder
            $folder = if ($ExportPath) { $ExportPath } else { $env:TEMP }

            # Create export folder if it doesn't exist
            if (-not (Test-Path $folder)) {
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
            }

            # Create a filename with computer name and timestamp
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $ext = switch ($ExportFormat) {
                'CSV'  { 'csv' }
                'JSON' { 'json' }
                'XML'  { 'xml' }
                'TXT'  { 'txt' }
            }

            $filename = "Services_${comp}_$timestamp.$ext"
            $filePath = Join-Path $folder $filename

            # Export the results to selected file type
            switch ($ExportFormat) {
                'CSV'  { $ResultList | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 }
                'JSON' { $ResultList | ConvertTo-Json -Depth 4 | Set-Content -Path $filePath -Encoding UTF8 }
                'XML'  { $ResultList | Export-Clixml -Path $filePath }
                'TXT'  { $ResultList | Out-String | Set-Content -Path $filePath -Encoding UTF8 }
            }
        }

        #---------------------- Show the results in console ----------------------#
        # Output the list of services to screen
        $ResultList

        #---------------------- Show export path after output ----------------------#
        # If export was done, print the full path to the saved file
        if ($filePath) {
            Write-Output "`nExported file saved to:`n$($filePath)`n"
        }

    } # end foreach comp

}

