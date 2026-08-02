[CmdletBinding()]
param(
	[string]$ArtifactPath,
	[string]$ArchivePassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$playbookRoot = $repoRoot
$validatePlaybook = Join-Path $PSScriptRoot 'validate-playbook.ps1'
$powerShell = (Get-Process -Id $PID).Path

function Invoke-CheckedScript {
	param(
		[Parameter(Mandatory)]
		[string]$ScriptPath,

		[Parameter(Mandatory)]
		[string[]]$Arguments
	)

	& $powerShell `
		-NoLogo `
		-NoProfile `
		-ExecutionPolicy Bypass `
		-File $ScriptPath `
		@Arguments
	if ($LASTEXITCODE -ne 0) {
		throw "Validation script failed with exit code $LASTEXITCODE`: $ScriptPath"
	}
}

function Resolve-SevenZip {
	foreach ($name in '7z.exe', '7za.exe', '7zz.exe', '7z', '7za', '7zz') {
		$command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
			Select-Object -First 1
		if ($command) {
			return $command.Source
		}
	}

	foreach ($candidate in @(
		(Join-Path ([Environment]::GetFolderPath('ProgramFiles')) '7-Zip\7z.exe'),
		(Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) '7-Zip\7z.exe')
	)) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			return $candidate
		}
	}

	throw '7-Zip or NanaZip was not found.'
}

function Test-RepositoryPowerShellSyntax {
	$parseFailures = [Collections.Generic.List[string]]::new()
	$excludedPrefixes = @(
		"$repoRoot\.git\"
	)
	$files = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
		Where-Object {
			$candidate = $_
			$candidate.Extension -in @('.ps1', '.psm1') -and
			-not ($excludedPrefixes | Where-Object {
				$candidate.FullName.StartsWith($_, [StringComparison]::OrdinalIgnoreCase)
			})
		}

	foreach ($file in $files) {
		$tokens = $null
		$errors = $null
		[void][Management.Automation.Language.Parser]::ParseFile(
			$file.FullName,
			[ref]$tokens,
			[ref]$errors
		)
		foreach ($parseError in $errors) {
			$relative = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
			$parseFailures.Add(
				'{0}:{1}:{2}: {3}' -f
				$relative,
				$parseError.Extent.StartLineNumber,
				$parseError.Extent.StartColumnNumber,
				$parseError.Message
			)
		}
	}

	if ($parseFailures.Count -ne 0) {
		throw "Repository PowerShell parse failures:`n$($parseFailures -join "`n")"
	}

	Write-Host "Repository PowerShell syntax passed ($($files.Count) files)." -ForegroundColor Green
}

Test-RepositoryPowerShellSyntax
Invoke-CheckedScript -ScriptPath $validatePlaybook -Arguments @('-Root', $playbookRoot)

if ([string]::IsNullOrWhiteSpace($ArtifactPath)) {
	Write-Host 'Source release validation passed.' -ForegroundColor Green
	return
}

$resolvedArtifact = (Resolve-Path -LiteralPath $ArtifactPath).Path
Invoke-CheckedScript `
	-ScriptPath $validatePlaybook `
	-Arguments @('-Root', $playbookRoot, '-ApbxPath', $resolvedArtifact)

$sevenZip = Resolve-SevenZip
$passwordArgument = if ([string]::IsNullOrEmpty($ArchivePassword)) {
	'-p'
} else {
	"-p$ArchivePassword"
}

& $sevenZip 't' '-y' $passwordArgument $resolvedArtifact | Out-Null
if ($LASTEXITCODE -ne 0) {
	throw "7-Zip archive test failed with exit code $LASTEXITCODE`: $resolvedArtifact"
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$extractRoot = Join-Path $tempBase ('playbook-release-' + [guid]::NewGuid().ToString('N'))
$resolvedExtractRoot = [IO.Path]::GetFullPath($extractRoot)
if (!$resolvedExtractRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
	throw "Refusing to use a temporary path outside the system temp directory: $resolvedExtractRoot"
}

New-Item -ItemType Directory -Path $resolvedExtractRoot | Out-Null
try {
	& $sevenZip 'x' '-y' $passwordArgument "-o$resolvedExtractRoot" $resolvedArtifact | Out-Null
	if ($LASTEXITCODE -ne 0) {
		throw "7-Zip extraction failed with exit code $LASTEXITCODE`: $resolvedArtifact"
	}

	Invoke-CheckedScript `
		-ScriptPath $validatePlaybook `
		-Arguments @('-Root', $resolvedExtractRoot)

	$sourceConfigHash = (Get-FileHash `
		-LiteralPath (Join-Path $playbookRoot 'playbook.conf') `
		-Algorithm SHA256).Hash
	$artifactConfigHash = (Get-FileHash `
		-LiteralPath (Join-Path $resolvedExtractRoot 'playbook.conf') `
		-Algorithm SHA256).Hash
	if ($sourceConfigHash -ne $artifactConfigHash) {
		throw 'The APBX playbook.conf does not match the validated source configuration.'
	}
}
finally {
	$verifiedExtractRoot = [IO.Path]::GetFullPath($resolvedExtractRoot)
	if (
		$verifiedExtractRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
		(Test-Path -LiteralPath $verifiedExtractRoot -PathType Container)
	) {
		Remove-Item -LiteralPath $verifiedExtractRoot -Recurse -Force
	}
}

Write-Host "Artifact release validation passed: $resolvedArtifact" -ForegroundColor Green
