[CmdletBinding()]
param(
    [Parameter()]
    [string]$Root,

    [Parameter()]
    [string]$ApbxPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..'
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$configurationRoot = Join-Path $resolvedRoot 'Configuration'
$failures = New-Object 'System.Collections.Generic.List[string]'
$checks = 0

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)

    $script:failures.Add($Message)
}

function Assert-RequiredFile {
    param([Parameter(Mandatory)][string]$RelativePath)

    $script:checks++
    $path = Join-Path $script:resolvedRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing required file: $RelativePath"
    }
}

function Test-PowerShellSyntax {
    $files = Get-ChildItem -LiteralPath $script:resolvedRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.psm1') }

    foreach ($file in $files) {
        $script:checks++
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$tokens,
            [ref]$errors
        )

        foreach ($parseError in $errors) {
            $relative = $file.FullName.Substring($script:resolvedRoot.Length).TrimStart('\', '/')
            $message = 'PowerShell parse error in {0}:{1}:{2}: {3}' -f @(
                $relative
                $parseError.Extent.StartLineNumber
                $parseError.Extent.StartColumnNumber
                $parseError.Message
            )
            Add-Failure $message
        }
    }
}

function Test-YamlSyntax {
    $script:checks++
    $validator = Join-Path $PSScriptRoot 'validate-yaml.py'
    if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
        Add-Failure "YAML validator is missing: $validator"
        return
    }

    $python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $python) {
        Add-Failure 'Python was not found; YAML syntax could not be validated.'
        return
    }

    $output = @(& $python.Source $validator $script:configurationRoot 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "YAML syntax validation failed:`n$($output -join "`n")"
        return
    }

    $output | Write-Host
}

function Test-PlaybookConfiguration {
    $configPath = Join-Path $script:resolvedRoot 'playbook.conf'
    $script:checks++

    try {
        [xml]$config = [IO.File]::ReadAllText($configPath)
    }
    catch {
        Add-Failure "playbook.conf is not valid XML: $($_.Exception.Message)"
        return
    }

    $playbook = $config.Playbook
    foreach ($field in @('Name', 'Username', 'Title', 'Version', 'UniqueId')) {
        $script:checks++
        if ([string]::IsNullOrWhiteSpace([string]$playbook.$field)) {
            Add-Failure "playbook.conf is missing a value for $field."
        }
    }

    $parsedVersion = $null
    $script:checks++
    if (-not [version]::TryParse([string]$playbook.Version, [ref]$parsedVersion)) {
        Add-Failure "playbook.conf has an invalid Version: $($playbook.Version)"
    }

    $parsedId = [guid]::Empty
    $script:checks++
    if (-not [guid]::TryParse([string]$playbook.UniqueId, [ref]$parsedId)) {
        Add-Failure "playbook.conf has an invalid UniqueId: $($playbook.UniqueId)"
    }

    $optionNames = @(
        $config.SelectNodes('/Playbook/FeaturePages//*[self::RadioOption or self::CheckboxOption or self::RadioImageOption]/Name') |
            ForEach-Object { $_.InnerText }
    )
    foreach ($duplicate in $optionNames | Group-Object | Where-Object Count -gt 1) {
        Add-Failure "Duplicate feature option name: $($duplicate.Name)"
    }

    foreach ($node in $config.SelectNodes('/Playbook/FeaturePages//*[@DefaultOption or @DependsOn]')) {
        foreach ($attributeName in @('DefaultOption', 'DependsOn')) {
            $attribute = $node.Attributes[$attributeName]
            if ($null -eq $attribute) {
                continue
            }

            $script:checks++
            if ($attribute.Value -notin $optionNames) {
                Add-Failure "Unknown $attributeName option '$($attribute.Value)' in playbook.conf."
            }
        }
    }

    $yamlOptionPattern = '(?im)\boption:\s*[''"]?(?<name>[a-z0-9][a-z0-9-]*)'
    foreach ($yamlFile in Get-ChildItem -LiteralPath $script:configurationRoot -Recurse -File -Include '*.yml', '*.yaml') {
        $content = [IO.File]::ReadAllText($yamlFile.FullName)
        foreach ($match in [regex]::Matches($content, $yamlOptionPattern)) {
            $script:checks++
            if ($match.Groups['name'].Value -notin $optionNames) {
                $relative = $yamlFile.FullName.Substring($script:resolvedRoot.Length).TrimStart('\', '/')
                Add-Failure "Unknown feature option in ${relative}: $($match.Groups['name'].Value)"
            }
        }
    }
}

function Test-YamlReferences {
    if (-not (Test-Path -LiteralPath $script:configurationRoot -PathType Container)) {
        Add-Failure 'Missing Configuration directory.'
        return
    }

    $taskPattern = '(?i)!task:\s*\{[^}\r\n]*path:\s*[''"](?<path>[^''"]+)[''"]'
    $filePattern = '(?i)(?<path>(?:Executables|Images)[\\/][^\r\n''"]+?\.(?:ps1|psm1|cmd|bat|reg|exe|xml|pow|png|jpg|jpeg|ico|url|lnk))'
    $yamlFiles = Get-ChildItem -LiteralPath $script:configurationRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.yml', '.yaml') }

    foreach ($yamlFile in $yamlFiles) {
        $content = [IO.File]::ReadAllText($yamlFile.FullName)
        $relativeYaml = $yamlFile.FullName.Substring($script:resolvedRoot.Length).TrimStart('\', '/')

        foreach ($match in [regex]::Matches($content, $taskPattern)) {
            $script:checks++
            $relativeTask = $match.Groups['path'].Value -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
            $target = Join-Path $script:configurationRoot $relativeTask
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                Add-Failure "Missing !task reference in ${relativeYaml}: $relativeTask"
            }
        }

        foreach ($match in [regex]::Matches($content, $filePattern)) {
            $script:checks++
            $relativeFile = $match.Groups['path'].Value -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
            $target = Join-Path $script:resolvedRoot $relativeFile
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                Add-Failure "Missing playbook file reference in ${relativeYaml}: $relativeFile"
            }
        }
    }
}

function Test-ComponentPackages {
    $packageRoot = Join-Path $script:resolvedRoot 'Executables\SystemRuntime\Packages'
    $manifestPath = Join-Path $packageRoot 'package-hashes.json'
    $script:checks++
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-Failure 'Missing component package hash manifest.'
        return
    }

    try {
        $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    }
    catch {
        Add-Failure "Invalid component package hash manifest: $($_.Exception.Message)"
        return
    }

    $cabFiles = @(Get-ChildItem -LiteralPath $packageRoot -File -Filter '*.cab')
    $manifestNames = @($manifest.PSObject.Properties.Name)
    $cabNames = @($cabFiles.Name)

    foreach ($name in $cabNames) {
        $script:checks++
        if ($name -notin $manifestNames) {
            Add-Failure "Component package is not present in package-hashes.json: $name"
            continue
        }

        $expectedHash = [string]$manifest.PSObject.Properties[$name].Value
        $script:checks++
        if ($expectedHash -notmatch '^[A-Fa-f0-9]{64}$') {
            Add-Failure "Invalid SHA-256 value for component package: $name"
            continue
        }

        $actualHash = (Get-FileHash -LiteralPath (Join-Path $packageRoot $name) -Algorithm SHA256).Hash
        $script:checks++
        if ($actualHash -ne $expectedHash) {
            Add-Failure "SHA-256 mismatch for component package: $name"
        }
    }

    foreach ($name in $manifestNames) {
        $script:checks++
        if ($name -notin $cabNames) {
            Add-Failure "package-hashes.json references a missing component package: $name"
        }
    }
}

function Test-ApbxArchive {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedApbx = (Resolve-Path -LiteralPath $Path).Path
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = $null

    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($resolvedApbx)
        $entries = @($archive.Entries)
        $entryNames = @($entries | ForEach-Object { $_.FullName -replace '\\', '/' })

        foreach ($required in @(
            'playbook.conf',
            'Configuration/custom.yml',
            'Configuration/tweaks.yml',
            'LICENSE',
            'NOTICE.md',
            'THIRD_PARTY_NOTICES.md',
            'Executables/SystemRuntime/Packages/package-hashes.json'
        )) {
            $script:checks++
            if ($required -notin $entryNames) {
                Add-Failure "APBX is missing required entry: $required"
            }
        }

        $script:checks++
        if (-not ($entryNames | Where-Object { $_ -like 'Executables/*' })) {
            Add-Failure 'APBX does not contain an Executables directory.'
        }

        foreach ($entryName in $entryNames) {
            $script:checks++
            if ($entryName.StartsWith('/') -or $entryName -match '(^|/)\.\.(/|$)') {
                Add-Failure "Unsafe APBX entry path: $entryName"
            }

            $isAllowedEntry = (
                $entryName -in @(
                    'playbook.conf',
                    'LICENSE',
                    'NOTICE.md',
                    'THIRD_PARTY_NOTICES.md'
                ) -or
                $entryName -match '^(?:Configuration|Executables|Images)/'
            )
            $script:checks++
            if (-not $isAllowedEntry) {
                Add-Failure "APBX contains a repository-only entry: $entryName"
            }
        }

        foreach ($duplicate in $entryNames | Group-Object | Where-Object Count -gt 1) {
            Add-Failure "Duplicate APBX entry: $($duplicate.Name)"
        }
    }
    catch {
        Add-Failure "Unable to read APBX archive '$resolvedApbx': $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

foreach ($requiredFile in @(
    'playbook.conf',
    'Configuration\custom.yml',
    'Configuration\tweaks.yml',
    'LICENSE',
    'NOTICE.md',
    'THIRD_PARTY_NOTICES.md'
)) {
    Assert-RequiredFile $requiredFile
}

Test-PowerShellSyntax
Test-YamlSyntax
Test-PlaybookConfiguration
Test-YamlReferences
Test-ComponentPackages

if ($PSBoundParameters.ContainsKey('ApbxPath')) {
    Test-ApbxArchive -Path $ApbxPath
}

if ($failures.Count -gt 0) {
    Write-Host "Playbook validation failed with $($failures.Count) error(s):" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Playbook validation passed ($checks checks)." -ForegroundColor Green
exit 0
