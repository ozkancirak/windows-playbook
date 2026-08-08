#Requires -Version 5.0
<#
    .SYNOPSIS
    Sets the Windows Reserved Storage state and verifies it actually changed.

    .DESCRIPTION
    The DISM PowerShell cmdlets are used instead of DISM.exe because its
    console output is localised and cannot be parsed on a non-English Windows.
#>

param (
    [ValidateSet('Disabled', 'Enabled')]
    [string]$State = 'Disabled'
)

$ErrorActionPreference = 'Stop'

Set-WindowsReservedStorageState -State $State | Out-Null

$actual = (Get-WindowsReservedStorageState).ReservedStorageState.ToString()
if ($actual -ne $State) {
    throw "Reserved storage is still '$actual' after requesting '$State'."
}

Write-Output "Reserved storage is now $State."
