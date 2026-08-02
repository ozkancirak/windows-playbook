#Requires -RunAsAdministrator

# GPL-3.0-only license
# 🦆 Modified from: https://github.com/he3als/online-sxs

param (
	[array]$InstallPackages,
	[array]$UninstallPackages,
	[string]$PackagesPath = "$([Environment]::GetFolderPath('Windows'))\SystemRuntime\Packages",
	[switch]$NoInteraction,
	[switch]$SafeMode,
	[switch]$FailMessage
)

if (!([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')) {
	throw "This script must be ran as TrustedInstaller/SYSTEM."
}

# ======================================================================================================================= #
# INITIAL VARIABLES                                                                                                       #
# ======================================================================================================================= #
$windir = [Environment]::GetFolderPath('Windows')
& "$windir\SystemRuntime\InitializePowerShell.ps1"
$sys32 = [Environment]::GetFolderPath('System')
$safeModePackageList = "$sys32\safeModePackagesToInstall.state"
$env:path = "$windir;$sys32;$sys32\Wbem;$sys32\WindowsPowerShell\v1.0;" + $env:path
$errorLevel = $warningLevel = 0

$arm = ((Get-CimInstance -Class Win32_ComputerSystem).SystemType -match 'ARM64') -or ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
$arch = if ($arm) {'arm64'} else {'amd64'}

$safeModeStatus = (Get-CimInstance -Class Win32_ComputerSystem).BootupState -ne 'Normal boot'

# ======================================================================================================================= #
# FUNCTIONS                                                                                                               #
# ======================================================================================================================= #
function Write-BulletPoint($message) {
	$message | Foreach-Object {
		Write-Host " - " -ForegroundColor Green -NoNewline
		Write-Host $_
	}
	Write-Host ""
}

function SafeMode {
	param (
		[switch]$Enable,
		[switch]$FailMessage,
		[array]$FailedPackageList,
		[string]$FailedPackageListPath = $safeModePackageList
	)

	if ($Enable) {
		$bcdeditArgs = '/set {current} safeboot minimal'
		$shellValue = "explorer.exe,cmd /c RunAsTI powershell -NoP -EP Unrestricted -File `"$PSCommandPath`" -SafeMode"

		if ($FailedPackageList) {
			Set-Content -Path $FailedPackageListPath -Value $FailedPackageList
		}
	} else {
		$bcdeditArgs = '/deletevalue {current} safeboot'
		$shellValue = 'explorer.exe'
	}

	if ($bcdeditArgs) { Start-Process -FilePath "bcdedit" -ArgumentList $bcdeditArgs -WindowStyle Hidden }
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name Shell -Value $shellValue -Force
}
if (
	($safeModeStatus -and
	(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name Shell).Shell -like "*$PSCommandPath*") -or
	$SafeMode
) {
	SafeMode
}

function Restart {
	shutdown /f /r /t 0 *>$null
	Start-Sleep 2
	Restart-Computer
	Start-Sleep 2
	Write-Host "Something seems to have went wrong restarting automatically, restart manually." -ForegroundColor Red
	if (!$NoInteraction) { Read-Pause }
	exit 9000
}

function Finish($failedPackages) {
	function GenerateText($text, $dashCount = 84) {
		$separator = "[ $('-' * $dashCount) ]"
		$text = "[ $text $(' ' * ($dashCount - $text.Length - 1)) ]"
		return @"
$separator
$text
$separator
"@
	}

	Write-Host "`n$(GenerateText "Completed! Errors: $script:errorLevel | Warnings: $script:warningLevel")`n" -ForegroundColor Green

	if ($failedPackages.Count -gt 0) {
		Write-Host "Some packages failed to install:" -ForegroundColor Red
		Write-BulletPoint $failedPackages

		if ($NoInteraction) {
			Write-Host "Setting error message box next boot as NoInteraction is enabled."
			Set-Content -Path $safeModePackageList -Value $failedPackages

			$failedMsgTitle = 'ComponentInstallFailure'
			$failedMsgArgs = "/c title Finalizing Installation & echo Do not close this window. & schtasks /delete /tn `"$failedMsgTitle`" /f > nul & " `
			+ "PowerShell -NoP -NonI -W Hidden -EP Bypass -C `"& '$PSCommandPath' -FailMessage`""
			$failedMsg = @{
				'TaskName'    = $failedMsgTitle
				'Settings'    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
				'Trigger'     = New-ScheduledTaskTrigger -AtLogOn
				'User'        = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
				'Force'       = $true
				'RunLevel'    = 'Highest'
				'Action'      = New-ScheduledTaskAction -Execute 'cmd' -Argument $failedMsgArgs
			}
			Register-ScheduledTask @failedMsg

			exit $script:errorLevel
		}

		function NoRestart {
			Write-Host "`nIf any packages installed successfully, they will apply next restart." -ForegroundColor Yellow
			Read-Pause
		}

		if ($safeModeStatus) {
			Write-Host "No automatic fallback is available after this Safe Mode failure." -ForegroundColor Magenta
			choice /c yn /n /m "Would you like to restart out of Safe Mode? [Y/N] "
			if ($lastexitcode -eq 1) {
				Restart
			} else {
				NoRestart
			}
		} else {
			choice /c yn /n /m "Would you like to boot into Safe Mode and attempt to install them? [Y/N] "
			if ($lastexitcode -eq 1) {
				SafeMode -Enable -FailedPackageList $failedPackages
				Restart
			} else {
				NoRestart
			}
		}

		exit $script:errorLevel
	}

	if ($NoInteraction) { exit $script:errorLevel }
	choice /c yn /n /m "Would you like to restart now to apply the changes? [Y/N] "
	if ($lastexitcode -eq 1) {
		Restart
	} else {
		Write-Host "`nChanges will apply next restart." -ForegroundColor Yellow
		Read-Pause
		exit $script:errorLevel
	}
}

# ======================================================================================================================= #
# UNINSTALL PACKAGES                                                                                                      #
# ======================================================================================================================= #
if ($UninstallPackages) {
	$installedPackages = @()
	$notInstalledPackages = $UninstallPackages
	(Get-WindowsPackage -Online).PackageName | ForEach-Object {
		foreach ($package in $UninstallPackages) {
			if (($_ -like $package) -and ($_ -match "$arch")) {
				$installedPackages += $_
				$notInstalledPackages = $notInstalledPackages -ne $package
				break
			}
		}
	}

	if ($installedPackages.Count -eq 0) {
		Write-Host "[WARN] '$UninstallPackages' matched no installed packages, nothing to do." -ForegroundColor Yellow
		$script:warningLevel++
	} else {
		if ($notMatchedPackages.Count -gt 0) {
			Write-Host "[WARN] Some packages not found to uninstall: $notMatchedPackages" -ForegroundColor Yellow
			$script:warningLevel++
		}

		foreach ($package in $installedPackages) {
			try {
				Write-Host "[INFO] Uninstalling '$package'..."
				Remove-WindowsPackage -Online -PackageName $package -NoRestart -LogLevel 1 *>$null
			} catch {
				Write-Host "[ERROR] $package failed to uninstall: $_" -ForegroundColor Red
				$script:errorLevel++
			}
		}
	}

	if (!$InstallPackages) {
		Finish
	}
}

# ======================================================================================================================= #
# PARSE $InstallPackages ARG                                                                                                     #
# ======================================================================================================================= #
if ($InstallPackages) {
	$matchedPackages = @()
	$notMatchedPackages = $InstallPackages
	(Get-ChildItem $PackagesPath -File -Filter "*.cab").FullName | Sort-Object -Descending | ForEach-Object {
		foreach ($package in $notMatchedPackages) {
			if (($_ -like $package) -and ($_ -match "$arch")) {
				$matchedPackages += $_
				$notMatchedPackages = $notMatchedPackages -ne $package
				break
			}
		}
	}

	if ($matchedPackages.Count -eq 0) {
		Write-Host "[ERROR] The specified CABs ($InstallPackages) to install weren't found." -ForegroundColor Red
		if (!$NoInteraction) { Read-Pause }
		exit 1
	}
	if ($notMatchedPackages.Count -gt 0) {
		Write-Host "[WARN] These CABs to install weren't found: $notMatchedPackages" -ForegroundColor Yellow
		$script:warningLevel++
	}
}

if ($SafeMode) {
	function ExitSafeModePrompt {
		choice /c yn /n /m "Would you like to restart to get out of Safe Mode? [Y/N] "
		if ($lastexitcode -eq 1) {
			Restart
		} else {
			exit 1
		}
	}

	$matchedPackages = Get-Content $safeModePackageList

	if ($matchedPackages.Count -le 0) {
		Write-Host "[ERROR] Safe Mode package list not found." -ForegroundColor Red
		ExitSafeModePrompt
	}

	$packagesThatDontExist = $matchedPackages | ForEach-Object { if (!(Test-Path $_ -PathType Leaf)) { $_ } }
	if ($packagesThatDontExist) {
		Write-Host "[ERROR] Some Safe Mode packages were not found." -ForegroundColor Red
		Write-BulletPoint $packagesThatDontExist
		ExitSafeModePrompt
	}
}

if ($FailMessage) {
	$body = @"
It appears that there was an issue while attempting to disable certain Windows components.

Would you like the playbook to restart your system into Safe Mode and try again? This process should not take much time.

If you chose to disable Windows Defender, it may remain enabled when selecting 'No'. You can retry later from the System Configuration folder.
"@

	if ((Read-MessageBox -Title "Component Modification" -Body $body -Icon Question) -eq 'Yes') {
		SafeMode -Enable
		Restart
	}

	exit
}

# ======================================================================================================================= #
# UI - SELECT PACKAGES                                                                                                    #
# ======================================================================================================================= #
if (!$matchedPackages) {
	Write-Host "This will install specified CBS packages online, meaning live on your current install of Windows." -ForegroundColor Yellow
	Read-Pause "Press Enter to continue"

	Write-Host "`n[INFO] Opening file dialog to select CBS package CAB..."
	Add-Type -AssemblyName System.Windows.Forms
	$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$openFileDialog.Multiselect = $true
	$openFileDialog.Filter = "CBS Package Files (*.cab)|*.cab"
	$openFileDialog.Title = "Select a CBS Package File"
	if ($openFileDialog.ShowDialog() -ne 'OK') {
		exit
	}
}

# ======================================================================================================================= #
# PROCESS PACKAGES                                                                                                        #
# ======================================================================================================================= #
function Remove-TrustedPackageCertificate {
	param(
		[Parameter(Mandatory = $true)]
		[Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
		[Parameter(Mandatory = $true)]
		[string[]]$StoreNames
	)

	foreach ($storeName in $StoreNames) {
		$store = [Security.Cryptography.X509Certificates.X509Store]::new(
			$storeName,
			[Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
		)
		try {
			$store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
			$store.Remove($Certificate)
		} finally {
			$store.Close()
		}
	}
}

function Add-TrustedPackageCertificate {
	param(
		[Parameter(Mandatory = $true)]
		[Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
	)

	$addedStores = @()
	try {
		foreach ($storeName in @('Root', 'TrustedPublisher')) {
			$store = [Security.Cryptography.X509Certificates.X509Store]::new(
				$storeName,
				[Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
			)
			try {
				$store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
				$existing = $store.Certificates.Find(
					[Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
					$Certificate.Thumbprint,
					$false
				)
				if ($existing.Count -eq 0) {
					$store.Add($Certificate)
					$addedStores += $storeName
				}
			} finally {
				$store.Close()
			}
		}
	} catch {
		if ($addedStores.Count -gt 0) {
			Remove-TrustedPackageCertificate -Certificate $Certificate -StoreNames $addedStores
		}
		throw
	}

	return $addedStores
}

function ProcessCab($cabPath) {
	$filePath = Split-Path $cabPath -Leaf
	Write-Host "`nInstalling $filePath..." -ForegroundColor Cyan
	Write-Host ("-" * 84) -ForegroundColor Magenta

	Write-Host "[INFO] Verifying package hash..."
	try {
		$hashManifestPath = Join-Path (Split-Path $cabPath -Parent) 'package-hashes.json'
		if (!(Test-Path $hashManifestPath -PathType Leaf)) {
			throw "Package hash manifest is missing: $hashManifestPath"
		}

		$hashManifest = Get-Content $hashManifestPath -Raw | ConvertFrom-Json
		$expectedHash = $hashManifest.PSObject.Properties[$filePath].Value
		if ($expectedHash -notmatch '^[A-Fa-f0-9]{64}$') {
			throw "No valid SHA-256 entry exists for '$filePath'."
		}

		$actualHash = (Get-FileHash $cabPath -Algorithm SHA256).Hash
		if ($actualHash -ne $expectedHash) {
			throw "SHA-256 mismatch for '$filePath'."
		}
	} catch {
		Write-Host "[ERROR] Package integrity error for '$cabPath': $_" -ForegroundColor Red
		$script:errorLevel++
		return $false
	}

	Write-Host "[INFO] Checking certificate..."
	$addedCertStores = @()
	try {
		$signature = Get-AuthenticodeSignature $cabPath
		$cert = $signature.SignerCertificate
		if (!$cert -or $signature.Status -in @('HashMismatch', 'NotSigned')) {
			throw "The CAB does not have an intact Authenticode signature."
		}
		if ($cert.Subject -ne 'CN=Local Playbook Components' -or $cert.Issuer -ne $cert.Subject) {
			throw "Unexpected package signer: '$($cert.Subject)'."
		}
		if ((Get-Date) -lt $cert.NotBefore -or (Get-Date) -gt $cert.NotAfter) {
			throw "The package signing certificate is outside its validity period."
		}

		$ekuExtension = $cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' }
		$ekuOids = @($ekuExtension.EnhancedKeyUsages | ForEach-Object { $_.Value })
		foreach ($requiredEku in @('1.3.6.1.4.1.311.10.3.6', '1.3.6.1.5.5.7.3.3')) {
			if ($requiredEku -notin $ekuOids) {
				throw "The package signer is missing required EKU '$requiredEku'."
			}
		}

		# The public certificate remains trusted because Windows servicing can need it
		# later when reading the package catalogs or the local repair source.
		$addedCertStores = @(Add-TrustedPackageCertificate -Certificate $cert)
	} catch {
		Write-Host "[ERROR] Cert error from '$cabPath': $_" -ForegroundColor Red
		$script:errorLevel++
		return $false
	}

	Write-Host "[INFO] Adding package..."
	try {
		Add-WindowsPackage -Online -PackagePath $cabPath -NoRestart -IgnoreCheck -LogLevel 1 *>$null
	} catch {
		if ($addedCertStores.Count -gt 0) {
			Remove-TrustedPackageCertificate -Certificate $cert -StoreNames $addedCertStores
		}
		Write-Host "[ERROR] Error when adding package '$cabPath': $_" -ForegroundColor Red
		$script:errorLevel++
		return $false
	}

	Write-Host "[INFO] Completed successfully."
	return $true
}

# Fixes RestoreHealth/SFC 'Sources' error
# https://learn.microsoft.com/windows-hardware/manufacture/desktop/configure-a-windows-repair-source
# Configure the local component payload as a Windows repair source
function MakeRepairSource {
	$version = '38655.38527.65535.65535'
	$srcPath = "%SystemRoot%\SystemRuntime\Packages\WinSxS"
	$srcPathExpanded = [System.Environment]::ExpandEnvironmentVariables($srcPath)

	Write-Host "`nMaking repair source..." -ForegroundColor Cyan
	Write-Host ("-" * 84) -ForegroundColor Magenta

	# Get the manifests installed by the component payload
	Write-Host "[INFO] Getting manifests..."
	$manifests = Get-ChildItem "$windir\WinSxS\Manifests" -File -Filter "*$version*"
	if ($manifests.Count -eq 0) {
		Write-Host "[WARN] No manifests found! Can't create repair source." -ForegroundColor Yellow
		return $false
	}

	# create new repair source folder
	if (Test-Path $srcPathExpanded -PathType Container) {
		Write-Host "[INFO] Deleting old RepairSrc..."
		Remove-Item $srcPathExpanded -Force -Recurse
	}
	Write-Host "[INFO] Creating RepairSrc path..."
	New-Item "$srcPathExpanded\Manifests" -Force -ItemType Directory | Out-Null

	# hardlink all the manifests to the repair source
	Write-Host "[INFO] Hard linking manifests..."
	foreach ($manifest in $manifests) {
		New-Item -ItemType HardLink -Path "$srcPathExpanded\Manifests\$manifest" -Target $manifest.FullName | Out-Null
	}

	# adds the repair source policy
	$servicingPolicyKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Servicing"
	if (!(Test-Path $servicingPolicyKey)) { New-Item -Path $servicingPolicyKey -Force | Out-Null }
	Set-ItemProperty -Path $servicingPolicyKey -Name LocalSourcePath -Value "$srcPath" -Type ExpandString -Force
}

if ($matchedPackages) {
	$packagesToProcess = $matchedPackages
} else {
	$packagesToProcess = $openFileDialog.FileNames
}

$successPackages = @()
$failedPackages = @()
$packagesToProcess | ForEach-Object {
	if (ProcessCab $_) {
		$successPackages += $_
	} else {
		$failedPackages += $_
	}
}

if ($successPackages.Count -ne 0) {
	MakeRepairSource
}

# ======================================================================================================================= #
# RESTART                                                                                                                 #
# ======================================================================================================================= #
Finish $failedPackages
