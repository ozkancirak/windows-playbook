param (
	[switch]$AddLiveLog,
	[switch]$ReplaceOldPlaybook,
	[switch]$DontOpenPbLocation,
	[switch]$NoPassword,
	[ValidateSet('Dependencies', 'Requirements', 'WinverRequirement', 'Verification', IgnoreCase = $true)]
	[array]$Removals,
	[string]$FileName,
	[string]$ArchivePassword = 'malte'
)

$removals | % { Set-Variable -Name "remove$_" -Value $true }

# Convert paths for convenience, needed for Linux/macOS
function Separator {
	return $args -replace '\\', "$([IO.Path]::DirectorySeparatorChar)"
}

# check 7z
if (Get-Command '7z' -EA 0) {
	$7zPath = '7z'
} elseif (Get-Command '7zz' -EA 0) {
	$7zPath = '7zz'
} elseif (!$IsLinux -and !$IsMacOS -and (Test-Path "$([Environment]::GetFolderPath('ProgramFiles'))\7-Zip\7z.exe")) {
	$7zPath = "$([Environment]::GetFolderPath('ProgramFiles'))\7-Zip\7z.exe"
} else {
	throw "This script requires 7-Zip or NanaZip to be installed to continue."
}

$currentDir = Get-Location
try {
	Set-Location -LiteralPath $PSScriptRoot
	if (!(Test-Path -LiteralPath 'playbook.conf' -PathType Leaf)) {
		throw "playbook.conf file not found next to build-playbook.ps1."
	}

if ($NoPassword -and $PSBoundParameters.ContainsKey('ArchivePassword')) {
	throw 'Use either -NoPassword or -ArchivePassword, not both.'
}
if ([string]::IsNullOrWhiteSpace($FileName)) {
	[xml]$playbookConfig = Get-Content -LiteralPath 'playbook.conf' -Raw
	$FileName = "Windows Playbook $($playbookConfig.Playbook.Version)"
}
if ($FileName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
	throw "FileName contains a character that is not valid in a file name: $FileName"
}

# check if old files are in use
$apbxFileName = "$fileName.apbx"
function GetNewName {
	while (Test-Path -Path $apbxFileName) {
		$num++
		$script:apbxFileName = "$fileName ($num).apbx"
	}
}
if ($replaceOldPlaybook -and (Test-Path -Path $apbxFileName)) {
	try {
		$stream = [System.IO.File]::Open($(Separator "$PWD\$apbxFileName"), 'Open', 'Read', 'Write')
		$stream.Close()
		Remove-Item -Path $apbxFileName -Force -EA 0
	} catch {
		Write-Warning "Couldn't replace '$apbxFileName', it's in use."
		GetNewName
	}
} elseif (Test-Path -Path $apbxFileName) {
	GetNewName
}
$apbxPath = Separator "$PWD\$apbxFileName"

# make temp directories
$rootTemp = New-Item (Join-Path -Path $([System.IO.Path]::GetTempPath()) -ChildPath $([System.Guid]::NewGuid())) -ItemType Directory -Force
if (!(Test-Path -Path "$rootTemp")) { throw "Failed to create temporary directory!" }
$playbookTemp = New-Item $(Separator "$rootTemp\playbook") -Type Directory

try {
	# remove entries in playbook config that make it awkward for testing
	$patterns = @()
	# 0.6.5 has a bug where it will crash without the 'Requirements' field, but all of the requirements are removed
	# "<Requirements>" and # "</Requirements>"
	if ($removeRequirements) {$patterns += "<Requirement>"}
	if ($removeWinverRequirement) {$patterns += "<string>", "</SupportedBuilds>", "<SupportedBuilds>"}
	if ($removeVerification) {$patterns += "<ProductCode>"}

	$tempPbConfPath = Separator "$playbookTemp\playbook.conf"
	if ($patterns.Count -gt 0) {
		Get-Content -Encoding "utf8" "playbook.conf" | Where-Object { $_ -notmatch ($patterns -join '|') } | Set-Content -Encoding "utf8" $tempPbConfPath
	}

	$customYmlPath = Separator "Configuration\custom.yml"
	$tempCustomYmlPath = Separator "$playbookTemp\$customYmlPath"
	if ($AddLiveLog) {
		if (Test-Path $customYmlPath -PathType Leaf) {
			New-Item (Split-Path $tempCustomYmlPath -Parent) -ItemType Directory -Force | Out-Null
			Copy-Item -Path $customYmlPath -Destination $tempCustomYmlPath -Force
			$customYml = Get-Content -Path $tempCustomYmlPath

			$liveLogScript = {
$a = Join-Path (Get-ChildItem (Join-Path $([Environment]::GetFolderPath('CommonApplicationData')) '\AME\Logs') -Directory |
Sort-Object LastWriteTime -Descending |
Select-Object -First 1).FullName '\OutputBuffer.txt';
while ($true) { Get-Content -Wait -LiteralPath $a -EA 0 | Write-Output; Start-Sleep 1 }
}
			[string]$liveLogText = ($liveLogScript -replace '"','"""' -replace "'","''").Trim() -replace "`r?`n", " "
			
			$actionsIndex = $customYml.IndexOf('actions:')
			$newCustomYml = $customYml[0..$actionsIndex] + `
				"  - !cmd: {command: 'start `"Playbook Live Log`" PowerShell -NoP -C `"$liveLogText`"'}" + `
				$customYml[($actionsIndex + 1)..($customYml.Count)]

			Set-Content -Path $tempCustomYmlPath -Value $newCustomYml
		} else {
			Write-Error "Can't find '$customYmlPath', not adding live log."
		}
	}

	$startYmlPath = Separator "Configuration\core\start.yml"
	$tempStartYmlPath = Separator "$playbookTemp\$startYmlPath"
	if ($removeDependencies) {
		if (Test-Path $startYmlPath -PathType Leaf) {
			New-Item (Split-Path $tempStartYmlPath -Parent) -ItemType Directory -Force | Out-Null
			Copy-Item -Path $startYmlPath -Destination $tempStartYmlPath -Force
			$startYml = Get-Content -Path $tempStartYmlPath

			$noLocalBuildStart = $startYml.IndexOf('  ################ NO LOCAL BUILD ################')
			$noLocalBuildEnd = $startYml.IndexOf('  ################ END NO LOCAL BUILD ################')
			$newStartYml = $startYml[0..($noLocalBuildStart - 1)] + `
				$startYml[($noLocalBuildEnd + 1)..($startYml.Count)]

			Set-Content -Path $tempStartYmlPath -Value $newStartYml
		} else {
			Write-Error "Can't find '$startYmlPath', not removing dependencies."
		}
	}

	# Package only playbook content. Repository metadata, build scripts, and
	# validation tools must never be included in the APBX artifact.
	$sourceFiles = @(
		foreach ($sourceDirectory in @('Configuration', 'Executables', 'Images')) {
			if (!(Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
				throw "Required playbook directory is missing: $sourceDirectory"
			}
			Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File
		}

		foreach ($sourceFile in @(
			'playbook.conf',
			'LICENSE',
			'NOTICE.md',
			'THIRD_PARTY_NOTICES.md'
		)) {
			if (!(Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
				throw "Required playbook file is missing: $sourceFile"
			}
			Get-Item -LiteralPath $sourceFile
		}
	)

	$excludedSourcePaths = [Collections.Generic.HashSet[string]]::new(
		[StringComparer]::OrdinalIgnoreCase
	)
	if (Test-Path $tempCustomYmlPath) {
		[void]$excludedSourcePaths.Add([IO.Path]::GetFullPath($customYmlPath))
	}
	if (Test-Path $tempStartYmlPath) {
		[void]$excludedSourcePaths.Add([IO.Path]::GetFullPath($startYmlPath))
	}
	if (Test-Path $tempPbConfPath) {
		[void]$excludedSourcePaths.Add([IO.Path]::GetFullPath('playbook.conf'))
	}

	$files = Separator "$rootTemp\7zFiles.txt"
	$sourceFiles |
		Where-Object {
			!$excludedSourcePaths.Contains([IO.Path]::GetFullPath($_.FullName))
		} |
		ForEach-Object {
			(Resolve-Path -LiteralPath $_.FullName -Relative).Substring(2)
		} |
		Out-File $files -Encoding utf8

	$passwordArguments = @()
	if (!$NoPassword -and -not [string]::IsNullOrEmpty($ArchivePassword)) {
		$passwordArguments += "-p$ArchivePassword"
	}

	& $7zPath a -spf -y -mx1 @passwordArguments -tzip "$apbxPath" `@"$files" | Out-Null
	if ($LASTEXITCODE -ne 0) {
		throw "7-Zip failed to create the APBX archive (exit code $LASTEXITCODE)."
	}
	# add edited files
	if (Test-Path $(Separator "$playbookTemp\*")) {
		Push-Location "$playbookTemp"
		try {
			& $7zPath u @passwordArguments "$apbxPath" * | Out-Null
			if ($LASTEXITCODE -ne 0) {
				throw "7-Zip failed to update the APBX archive (exit code $LASTEXITCODE)."
			}
		} finally {
			Pop-Location
		}
	}

	# Stupid hack because "The process cannot access the file because it is being used by another process." happens now and I have no idea why
	$apbxTmpPath = $apbxPath + '.tmp'
	if (Test-Path $apbxTmpPath) {
		Remove-Item -Path $apbxPath
		Rename-Item -Path $apbxTmpPath -NewName $apbxPath 
	}
	if (
		!(Test-Path -LiteralPath $apbxPath -PathType Leaf) -or
		(Get-Item -LiteralPath $apbxPath).Length -le 0
	) {
		throw "APBX output is missing or empty: $apbxPath"
	}
	Write-Host "Built successfully! Path: `"$apbxPath`"" -ForegroundColor Green
	if (!$DontOpenPbLocation) {
		if ($IsLinux -or $IsMacOS) {
			Write-Warning "Can't open to APBX directory as the system isn't Windows."
		} else {
			# Kill old instances
			# Would use SetForegroundWindow but it doesn't always work, so opening a new window is most reliable :/
			$openWindows = ((New-Object -Com Shell.Application).Windows() | Where-Object { $_.Document.Folder.Self.Path -eq "$(Split-Path -Path $apbxPath)" })
			if ($openWindows.Count -ne 0) { $openWindows.Quit() }

			explorer /select,"$apbxPath"
		}
	}
} finally {
	Remove-Item $rootTemp -Force -EA 0 -Recurse | Out-Null
}
} finally {
	Set-Location -LiteralPath $currentDir
}
