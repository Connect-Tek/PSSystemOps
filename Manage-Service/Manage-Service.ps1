function Manage-Service {
<#
.SYNOPSIS
    Manage a specific Windows service on one or more computers.

.DESCRIPTION
    This function allows you to manage a service by its exact name or display name
    on local or remote computers. You can start, stop, or restart a service, and 
    optionally modify its startup type (e.g. Automatic, Manual, Disabled).

.PARAMETER Name
    The exact name or display name of the service to manage. This parameter is required.

.PARAMETER ComputerName
    One or more target computers where the service should be managed.
    Defaults to the local computer if not specified.

.PARAMETER Start
    Starts the specified service on the target computer(s).

.PARAMETER Stop
    Stops the specified service on the target computer(s). Uses the -Force switch.

.PARAMETER Restart
    Restarts the specified service on the target computer(s).
    Note: Restarting a service that is currently stopped is not prevented.

.PARAMETER StartupType
    Changes the service's startup type to one of the following: Automatic, Manual, Disabled.

.EXAMPLE
    Manage-Service -Name "Spooler" -Start

    Starts the Print Spooler service on the local computer.

.EXAMPLE
    Manage-Service -Name "W32Time" -ComputerName "Server01","Server02" -Stop -StartupType Disabled

    Stops and disables the Windows Time service on Server01 and Server02.

.EXAMPLE
    Manage-Service -Name "Spooler" -ComputerName "TEK-DC01" -Restart -StartupType Automatic

    Restarts and sets the Spooler service to start automatically on TEK-DC01.

.NOTES
    Author: Your Name
    Created: 2025-07-30
    Requires:
    - Administrative privileges on target machines.
    - PowerShell Remoting must be enabled for remote management.

    Limitations:
    - Restarting a service that is currently stopped is allowed without validation.
      A warning will be shown but the action will still be attempted.
    - Some services may not allow their startup type to be changed due to system policies or permissions.
#>

    [CmdletBinding()]
    param (
        # Service name or display name (must match exactly)
        [Parameter(Mandatory)]
        [string]$Name,

        # One or more computer names to target (defaults to local machine)
        [string[]]$ComputerName = $env:COMPUTERNAME,

        # Perform service actions
        [switch]$Start,
        [switch]$Stop,
        [switch]$Restart,

        # Set startup type (Automatic, Manual, Disabled)
        [ValidateSet('Automatic', 'Manual', 'Disabled')]
        [string]$StartupType
    )

    foreach ($computer in $ComputerName) {
        Write-Host "`n========== [$computer] ==========" -ForegroundColor Cyan

        try {
            # Get the service using CIM
            $Service = Get-CimInstance -ClassName Win32_Service -ComputerName $computer -ErrorAction Stop |
                Where-Object { $_.Name -eq $Name -or $_.DisplayName -eq $Name }

            if (-not $Service) {
                Write-Warning "Service '$Name' not found on '$computer'"
                continue
            }

            # Perform service actions
            if ($Start) {
                Invoke-Command -ComputerName $computer -ScriptBlock {
                    param($svcName)
                    Start-Service -Name $svcName
                } -ArgumentList $Name
            }

            if ($Stop) {
                Invoke-Command -ComputerName $computer -ScriptBlock {
                    param($svcName)
                    Stop-Service -Name $svcName -Force
                } -ArgumentList $Name
            }

            if ($Restart) {
                Invoke-Command -ComputerName $computer -ScriptBlock {
                    param($svcName)
                    Restart-Service -Name $svcName
                } -ArgumentList $Name
            }

            # Set startup type using CIM
            if ($StartupType) {
                try {
                    $changeResult = Invoke-Command -ComputerName $computer -ScriptBlock {
                        param($svcName, $startType)
                        $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$svcName'"
                        if ($svc) {
                            Invoke-CimMethod -InputObject $svc -MethodName 'ChangeStartMode' -Arguments @{ StartMode = $startType }
                        }
                    } -ArgumentList $Name, $StartupType

                    if ($changeResult -and $changeResult.ReturnValue -ne 0) {
                        Write-Warning "Failed to change StartupType on '$computer'. WMI returned code: $($changeResult.ReturnValue)"
                    }
                }
                catch {
                    Write-Warning "Access denied or unsupported operation when setting StartupType on '$computer'."
                }
            }

            # Re-fetch and display updated status
            $UpdatedService = Get-CimInstance -ClassName Win32_Service -ComputerName $computer -ErrorAction Stop |
                Where-Object { $_.Name -eq $Name -or $_.DisplayName -eq $Name }

            $UpdatedService |
                Select-Object ProcessId, Name, StartMode, State, Status |
                Format-Table -AutoSize
        }
        catch {
            Write-Error "Error managing service '$Name' on '$computer': $_"
        }
    }
}
