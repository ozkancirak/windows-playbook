#Requires -Version 5.0
<#
    .SYNOPSIS
    Stops or restores delivery of the Malicious Software Removal Tool (MSRT).

    .DESCRIPTION
    Disabled: blocks MSRT in Windows Update and removes MRT.exe.
    Enabled:  removes the block and clears the recorded MSRT version, so
              Windows Update offers the tool again and reinstalls MRT.exe.
              Without clearing the version Windows believes the current
              version is installed and never redelivers the removed file.
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('Disabled', 'Enabled')]
    [string]$State
)

$ErrorActionPreference = 'Stop'

$policy  = 'HKLM:\SOFTWARE\Policies\Microsoft\MRT'
$version = 'HKLM:\SOFTWARE\Microsoft\RemovalTools\MRT'
$mrt     = Join-Path ([Environment]::GetFolderPath('System')) 'MRT.exe'

if ($State -eq 'Disabled') {
    $null = New-Item -Path $policy -Force
    Set-ItemProperty -LiteralPath $policy -Name 'DontOfferThroughWUAU' -Value 1 -Type DWord -Force

    if (Test-Path -LiteralPath $mrt) {
        try {
            Remove-Item -LiteralPath $mrt -Force
        }
        catch {
            # MRT.exe is owned by TrustedInstaller.
            & takeown.exe /f $mrt | Out-Null
            & icacls.exe $mrt /grant '*S-1-5-32-544:F' | Out-Null
            Remove-Item -LiteralPath $mrt -Force
        }
    }

    Write-Output 'MSRT blocked in Windows Update and MRT.exe removed.'
}
else {
    Remove-ItemProperty -LiteralPath $policy -Name 'DontOfferThroughWUAU' -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $mrt) {
        # MRT.exe is still there, so the recorded version is genuine.
        # Clearing it would make Windows Update redownload it for nothing.
        Write-Output 'MSRT unblocked.'
    }
    else {
        Remove-ItemProperty -LiteralPath $version -Name 'Version' -Force -ErrorAction SilentlyContinue
        Write-Output 'MSRT unblocked. Windows Update will reinstall MRT.exe on its next scan.'
    }
}
