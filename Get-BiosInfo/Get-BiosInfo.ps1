function Get-BiosInfo {
<#
.SYNOPSIS
    Retrieves BIOS and system product information from local or remote computers.

.DESCRIPTION
    This script gathers detailed BIOS and system product information using WMI (Win32_BIOS and Win32_ComputerSystemProduct).
    It supports multiple computer names and can optionally export results in various formats.

.PARAMETER ComputerName
    A string or array of computer names to query.
    Defaults to the local computer if not specified.

.PARAMETER ExportFormat
    Specifies the format to export the data. Supported formats: CSV, JSON, XML, TXT, HTML.

.PARAMETER ExportPath
    Optional path to save the exported file. If not provided, a temporary directory is used.

.PARAMETER Raw
    Outputs raw CIM objects instead of filtered/custom object.

.EXAMPLE
    Get-BiosInfo
    Retrieves BIOS info from the local computer.

.EXAMPLE
    Get-BiosInfo -ComputerName "Server01", "Server02"
    Retrieves BIOS info from two remote servers.

.EXAMPLE
    Get-BiosInfo -ComputerName "Server01" -ExportFormat CSV -ExportPath "C:\Reports"
    Retrieves BIOS info from Server01 and exports it as a CSV file to C:\Reports.

.EXAMPLE
    Get-BiosInfo -Raw
    Retrieves raw WMI objects from the local computer.

.LIMITATIONS
    - Remote execution requires WinRM to be enabled and accessible on the target machines.
    - Error handling is basic; failures per computer will output a warning.
    - Export folder must be writable; creation attempt is made if missing.

.REQUIREMENTS
    - PowerShell 5.1 or later.
    - Administrator rights may be required depending on the environment and remote access settings.
    - WinRM must be configured and allowed between systems for remote execution.

.NOTES
    Author: ConnectTek
    Last Updated: 07/08/2025
#>

    [CmdletBinding()]
    param (
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [ValidateSet('CSV', 'JSON', 'XML', 'TXT', 'HTML')]
        [string]$ExportFormat,

        [string]$ExportPath,

        [switch]$Raw
    )

    $scriptBlock = {
        param($rawFlag)

        try {
            $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
            $sysProd = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop
        }
        catch {
            Write-Warning "[$env:COMPUTERNAME] Data retrieval failed: $($_.Exception.Message)"
            return
        }

        if ($rawFlag) {
            return [pscustomobject]@{
                ComputerName  = $env:COMPUTERNAME
                BIOS          = $bios
                SystemProduct = $sysProd
            }
        }
        else {
            return [pscustomobject]@{
                'ComputerName'      = $env:COMPUTERNAME
                'ProductName'       = $sysProd.Name
                'IdentifyingNumber' = $sysProd.IdentifyingNumber
                'UUID'              = $sysProd.UUID
                'BIOS_Name'         = $bios.Name
                'Manufacturer'      = $bios.Manufacturer
                'SerialNumber'      = $bios.SerialNumber
                'Version'           = $bios.Version
                'SMBiosBiosVersion' = $bios.SMBiosBiosVersion
                'BuildNumber'       = $bios.BuildNumber
                'ReleaseDate'       = $bios.ReleaseDate
                'CurrentLanguage'   = $bios.CurrentLanguage
                'Status'            = $bios.Status
            }
        }
    }

    $results = foreach ($comp in $ComputerName) {
        try {
            if ($comp -eq $env:COMPUTERNAME) {
                & $scriptBlock $Raw
            } else {
                Invoke-Command -ComputerName $comp -ScriptBlock $scriptBlock -ArgumentList $Raw -ErrorAction Stop
            }
        }
        catch {
            Write-Warning "Failed to retrieve info from '$comp': $($_.Exception.Message)"
        }
    }

    if ($Raw) { return $results }

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
        $filename = "BiosInfo_$timestamp.$ext"
        $filePath = Join-Path $folder $filename

        try {
            switch ($ExportFormat) {
                'CSV'  { $results | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 }
                'JSON' { $results | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8 }
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

