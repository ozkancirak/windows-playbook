$configurationRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\Configuration')
)
$configurationPrefix = $configurationRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
) + [System.IO.Path]::DirectorySeparatorChar

$taskPattern = [regex]::new(
    '^(?!\s*#).*?!task\s*:\s*\{[^}\r\n]*?\bpath\s*:\s*[''"](?<path>[^''"]+)[''"]',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Multiline
)
$pendingYamlFiles = New-Object System.Collections.Generic.Stack[string]
$activeYamlFiles = New-Object System.Collections.Generic.HashSet[string](
    [System.StringComparer]::OrdinalIgnoreCase
)
$pendingYamlFiles.Push((Join-Path $configurationRoot 'custom.yml'))

while ($pendingYamlFiles.Count -gt 0) {
    $yamlFile = [System.IO.Path]::GetFullPath($pendingYamlFiles.Pop())
    if (-not $yamlFile.StartsWith($configurationPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "YAML task path escapes the Configuration directory: '$yamlFile'."
    }
    if (-not (Test-Path -LiteralPath $yamlFile -PathType Leaf)) {
        throw "Referenced YAML task was not found: '$yamlFile'."
    }
    if (-not $activeYamlFiles.Add($yamlFile)) {
        continue
    }

    $yamlContent = Get-Content -LiteralPath $yamlFile -Raw -ErrorAction Stop
    foreach ($match in $taskPattern.Matches($yamlContent)) {
        $taskPath = Join-Path $configurationRoot $match.Groups['path'].Value
        $pendingYamlFiles.Push($taskPath)
    }
}

$registryPaths = New-Object System.Collections.Generic.HashSet[string](
    [System.StringComparer]::OrdinalIgnoreCase
)
$pathPattern = [regex]::new(
    '^(?!\s*#).*?\bpath\s*:\s*[''"]HKCU\\(?<path>[^''"]+)[''"]',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Multiline
)
$registryActionPattern = [regex]::new(
    '^(?!\s*#)\s*-\s*!(?<type>registryKey|registryValue)\s*:',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$yamlActionPattern = [regex]::new('^(?!\s*#)\s*-\s*![A-Za-z][A-Za-z0-9]*\s*:')
$actionPathPattern = [regex]::new(
    '^(?!\s*#).*?\bpath\s*:\s*[''"]HKCU\\(?<path>[^''"]+)[''"]',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Multiline
)
$actionOperationPattern = [regex]::new(
    '^(?!\s*#).*?\boperation\s*:\s*[''"]?(?<operation>[A-Za-z]+)',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Multiline
)
$actionValuePattern = [regex]::new(
    '^(?!\s*#).*?\bvalue\s*:\s*(?:[''"](?<quoted>[^''"]*)[''"]|(?<plain>[^,}\s#]+))',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Multiline
)
$deletedRegistryKeys = New-Object System.Collections.Generic.HashSet[string](
    [System.StringComparer]::OrdinalIgnoreCase
)
$deletedRegistryValues = New-Object System.Collections.Generic.List[object]

function Add-RegistryDeletion {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('registryKey', 'registryValue')]
        [string]$ActionType,

        [Parameter(Mandatory = $true)]
        [string]$ActionText
    )

    $pathMatch = $actionPathPattern.Match($ActionText)
    if (-not $pathMatch.Success) {
        return
    }

    $relativePath = $pathMatch.Groups['path'].Value.Trim()
    $operationMatch = $actionOperationPattern.Match($ActionText)
    $operation = if ($operationMatch.Success) {
        $operationMatch.Groups['operation'].Value
    }
    else {
        ''
    }

    if ($ActionType -eq 'registryKey') {
        if ($operation -ne 'add') {
            $null = $deletedRegistryKeys.Add($relativePath)
        }
        return
    }

    if ($operation -ne 'delete') {
        return
    }

    $valueMatch = $actionValuePattern.Match($ActionText)
    if (-not $valueMatch.Success) {
        throw "A registryValue delete action for '$relativePath' has no value name."
    }

    $valueName = if ($valueMatch.Groups['quoted'].Success) {
        $valueMatch.Groups['quoted'].Value
    }
    else {
        $valueMatch.Groups['plain'].Value
    }
    $deletedRegistryValues.Add([pscustomobject]@{
        Path = $relativePath
        Name = $valueName
    })
}

foreach ($yamlFile in $activeYamlFiles) {
    $yamlContent = Get-Content -LiteralPath $yamlFile -Raw -ErrorAction Stop
    foreach ($match in $pathPattern.Matches($yamlContent)) {
        $relativePath = $match.Groups['path'].Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($relativePath)) {
            $null = $registryPaths.Add($relativePath)
        }
    }

    $currentActionType = $null
    $currentActionLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($yamlContent -split '\r?\n')) {
        $actionMatch = $registryActionPattern.Match($line)
        if ($actionMatch.Success) {
            if ($null -ne $currentActionType) {
                Add-RegistryDeletion -ActionType $currentActionType `
                    -ActionText ($currentActionLines -join [Environment]::NewLine)
            }

            $currentActionType = $actionMatch.Groups['type'].Value
            $currentActionLines.Clear()
            $currentActionLines.Add($line)
            continue
        }

        if ($yamlActionPattern.IsMatch($line)) {
            if ($null -ne $currentActionType) {
                Add-RegistryDeletion -ActionType $currentActionType `
                    -ActionText ($currentActionLines -join [Environment]::NewLine)
            }

            $currentActionType = $null
            $currentActionLines.Clear()
            continue
        }

        if ($null -ne $currentActionType) {
            $currentActionLines.Add($line)
        }
    }

    if ($null -ne $currentActionType) {
        Add-RegistryDeletion -ActionType $currentActionType `
            -ActionText ($currentActionLines -join [Environment]::NewLine)
    }
}

if ($registryPaths.Count -eq 0) {
    throw 'No HKCU registry paths were found in tweak YAML files.'
}

$defaultUserHive = [Microsoft.Win32.Registry]::Users.OpenSubKey('AME_UserHive_Default', $true)
if ($null -eq $defaultUserHive) {
    throw 'The Default User registry hive is not loaded at HKU\AME_UserHive_Default.'
}

try {
    foreach ($relativePath in ($registryPaths | Sort-Object)) {
        $sourceKey = $null
        $destinationKey = $null

        try {
            if ($deletedRegistryKeys.Contains($relativePath)) {
                $defaultUserHive.DeleteSubKeyTree($relativePath, $false)
            }

            $sourceKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($relativePath, $false)
            if ($null -eq $sourceKey) {
                $destinationKey = $defaultUserHive.OpenSubKey($relativePath, $true)
            }
            else {
                $destinationKey = $defaultUserHive.CreateSubKey($relativePath)
                if ($null -eq $destinationKey) {
                    throw "Failed to create Default User registry key '$relativePath'."
                }
            }

            $sourceValueNames = New-Object System.Collections.Generic.HashSet[string](
                [System.StringComparer]::OrdinalIgnoreCase
            )

            if ($null -ne $sourceKey) {
                foreach ($valueName in $sourceKey.GetValueNames()) {
                    $null = $sourceValueNames.Add($valueName)
                    $value = $sourceKey.GetValue(
                        $valueName,
                        $null,
                        [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
                    )
                    $valueKind = $sourceKey.GetValueKind($valueName)
                    $destinationKey.SetValue($valueName, $value, $valueKind)
                }
            }

            foreach ($deletedValue in ($deletedRegistryValues | Where-Object Path -EQ $relativePath)) {
                if (
                    $null -ne $destinationKey -and
                    -not $sourceValueNames.Contains($deletedValue.Name)
                ) {
                    $destinationKey.DeleteValue($deletedValue.Name, $false)
                }
            }
        }
        finally {
            if ($null -ne $destinationKey) {
                $destinationKey.Dispose()
            }
            if ($null -ne $sourceKey) {
                $sourceKey.Dispose()
            }
        }
    }
}
finally {
    $defaultUserHive.Dispose()
}
