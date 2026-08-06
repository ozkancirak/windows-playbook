if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { 
  Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit 
}

$windir = [Environment]::GetFolderPath('Windows')
& "$windir\SystemRuntime\InitializePowerShell.ps1"
$systemConfig = "$windir\SystemConfig"
$systemRuntime = "$windir\SystemRuntime"

$title = 'Preparing user settings...'

if (!(Test-Path $systemConfig) -or !(Test-Path $systemRuntime)) {
    Write-Host "The playbook could not configure user settings because its files were not found." -ForegroundColor Red
    Read-Pause
    exit 1
}

$Host.UI.RawUI.WindowTitle = $title
Write-Host $title -ForegroundColor Yellow
Write-Host $('-' * ($title.length + 3)) -ForegroundColor Yellow
Write-Host "You'll be logged out in 10 to 20 seconds, and once you login again, your new account will be ready for use."

# Disable Windows 11 context menu & 'Gallery' in File Explorer
if ([System.Environment]::OSVersion.Version.Build -ge 22000) {
    & "$systemConfig\4. Interface Tweaks\Context Menus\Windows 11\Old Context Menu (default).cmd" /silent
    & "$systemConfig\4. Interface Tweaks\File Explorer Customization\Gallery\Disable Gallery (default).cmd" /silent

}

# Disable 'Network' in navigation pane
& "$systemConfig\3. General Configuration\File Sharing\Network Navigation Pane\Disable Network Navigation Pane (default).cmd" /silent

# Disable Automatic Folder Discovery
& "$systemConfig\4. Interface Tweaks\File Explorer Customization\Automatic Folder Discovery\Disable Automatic Folder Discovery (default).cmd" /silent

# Set visual effects
& "$systemConfig\4. Interface Tweaks\Visual Effects (Animations)\Optimized Visual Effects (default).cmd" /silent

# Set taskbar pins
$browser = $null
try {
    $browser = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\SystemConfig\SetupOptions' -Name 'Browser' -ErrorAction Stop
}
catch {
    Write-Warning 'No saved browser selection was found; using the taskbar fallback.'
}

if ([string]::IsNullOrWhiteSpace([string]$browser)) {
    $browser = $null
}

& "$systemRuntime\Scripts\ConfigureTaskbarPins.ps1" -Browser $browser
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1

# Leave
Start-Sleep 5 
logoff
