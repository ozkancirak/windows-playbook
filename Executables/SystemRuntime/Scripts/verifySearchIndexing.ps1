[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Disabled', 'Minimal', 'Enabled')]
    [string]$State,

    [ValidateRange(0, 1)]
    [int]$RespectPowerModes = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$ExpectedValue
    )

    $registryValues = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    $property = $registryValues.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Missing registry value '$Path\$Name'."
    }

    $actualValue = $property.Value
    if ($actualValue -ne $ExpectedValue) {
        throw "Unexpected value for '$Path\$Name': expected '$ExpectedValue', found '$actualValue'."
    }
}

function Assert-IndexPath {
    param(
        [Parameter(Mandatory)][string[]]$RegistryPaths,
        [Parameter(Mandatory)][string]$FileSystemPath
    )

    $indexPath = "file:///$FileSystemPath\*"
    foreach ($registryPath in $RegistryPaths) {
        Assert-RegistryValue -Path $registryPath -Name $indexPath -ExpectedValue $indexPath
    }
}

function Assert-IndexPathAbsent {
    param(
        [Parameter(Mandatory)][string[]]$RegistryPaths,
        [Parameter(Mandatory)][string]$FileSystemPath
    )

    $indexPath = "file:///$FileSystemPath\*"
    foreach ($registryPath in $RegistryPaths) {
        $registryValues = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
        if ($null -ne $registryValues.PSObject.Properties[$indexPath]) {
            throw "Unexpected index path '$indexPath' in '$registryPath'."
        }
    }
}

try {
    $service = Get-Service -Name 'WSearch' -ErrorAction Stop
    $servicePath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\WSearch'

    if ($State -eq 'Disabled') {
        Assert-RegistryValue -Path $servicePath -Name 'Start' -ExpectedValue 4
        if ([string]$service.Status -ne 'Stopped') {
            throw "WSearch is '$($service.Status)' instead of 'Stopped'."
        }
    }
    else {
        Assert-RegistryValue -Path $servicePath -Name 'Start' -ExpectedValue 2
        Assert-RegistryValue -Path $servicePath -Name 'DelayedAutoStart' -ExpectedValue 1
        if ([string]$service.Status -ne 'Running') {
            throw "WSearch is '$($service.Status)' instead of 'Running'."
        }

        $indexedPaths = @(
            'Registry::HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\Windows Search\DefaultIndexedPaths'
            'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows Search\CurrentPolicies\DefaultIndexedPaths'
        )
        $excludedPaths = @(
            'Registry::HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\Windows Search\DefaultExcludedPaths'
            'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows Search\CurrentPolicies\DefaultExcludedPaths'
        )

        Assert-IndexPath -RegistryPaths $indexedPaths -FileSystemPath "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
        Assert-IndexPath -RegistryPaths $indexedPaths -FileSystemPath "$env:windir\SystemConfig"

        if ($State -eq 'Minimal') {
            Assert-IndexPath -RegistryPaths $excludedPaths -FileSystemPath "$env:SystemDrive\Users"
            Assert-IndexPathAbsent -RegistryPaths $indexedPaths -FileSystemPath "$env:SystemDrive\Users"
        }
        else {
            Assert-IndexPath -RegistryPaths $indexedPaths -FileSystemPath "$env:SystemDrive\Users"
            Assert-IndexPathAbsent -RegistryPaths $excludedPaths -FileSystemPath "$env:SystemDrive\Users"
        }

        Assert-RegistryValue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Search' -Name 'SetupCompletedSuccessfully' -ExpectedValue 0
        Assert-RegistryValue -Path 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows Search\Gather\Windows\SystemIndex' -Name 'RespectPowerModes' -ExpectedValue $RespectPowerModes
    }
}
catch {
    Write-Error "Search Indexing verification failed: $($_.Exception.Message)"
    exit 1
}

exit 0
