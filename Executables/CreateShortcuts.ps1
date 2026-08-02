.\SystemRuntime\InitializePowerShell.ps1
$windir = [Environment]::GetFolderPath('Windows')

Write-Title "Creating Desktop & Start Menu shortcuts..."

# Default user
$defaultShortcut = "$(Get-UserPath)\System Configuration.lnk"
New-Shortcut -Source "$windir\SystemConfig" -Destination $defaultShortcut -Icon "$windir\System32\shell32.dll,316"

# Copy shortcut to every user
foreach ($userKey in (Get-RegUserPaths -NoDefault).PsPath) {
	$folders = Get-ItemProperty -path "$userKey\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
	$deskPath = $folders.Desktop
	if (Test-Path $deskPath -PathType Container) {
		Write-Output "Copying Desktop shortcut for '$userKey'..."
		Copy-Item $defaultShortcut -Destination $deskPath -Force
	} else {
		Write-Error "Desktop path not found for '$userKey', shortcuts can't be copied."
	}
}

# Start menu shortcut
Copy-Item $defaultShortcut -Destination "$([Environment]::GetFolderPath('CommonStartMenu'))\Programs" -Force

Write-Title "Creating services restore shortcut..."
$desktop = "$windir\SystemConfig"
New-Shortcut -Source "$desktop\9. Troubleshooting\Set services to defaults.cmd" -Destination "$desktop\6. Advanced Configuration\Services\Set services to defaults.lnk"
