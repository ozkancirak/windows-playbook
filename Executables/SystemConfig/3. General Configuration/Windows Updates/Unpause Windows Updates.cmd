@echo off
setlocal

set "___args="%~f0" %*"
fltmc > nul 2>&1 || (
	echo Administrator privileges are required.
	powershell -c "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList """/c $env:___args"""" 2> nul || (
		echo You must run this script as admin.
		if "%*"=="" pause
		exit /b 1
	)
	exit /b
)

echo Resetting Windows Update pause policies...

:: Deferral values are owned by "Set/Reset Windows Update Deferral.cmd"
:: and are deliberately left untouched here.

for %%K in (Feature Quality) do (
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v Pause%%KUpdates /f > nul 2>&1
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v Pause%%KUpdatesStartTime /f > nul 2>&1
)

reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings" /v PausedFeatureStatus /t REG_DWORD /d 0 /f > nul
reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings" /v PausedQualityStatus /t REG_DWORD /d 0 /f > nul

set "_uxKey=HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
for %%V in (PauseFeatureUpdatesStartTime PauseFeatureUpdatesEndTime PauseQualityUpdatesStartTime PauseQualityUpdatesEndTime PauseUpdatesStartTime PauseUpdatesExpiryTime PausedFeatureStatus PausedQualityStatus FlightSettingsMaxPauseDays HideMCTLink RestartNotificationsAllowed2) do (
    reg delete "%_uxKey%" /v %%V /f > nul 2>&1
)

reg delete "HKLM\SYSTEM\Setup\UpgradeNotification" /v UpgradeAvailable /f > nul 2>&1

echo Done. Windows Updates have been unpaused.
if "%~1"=="/silent" exit /b
pause
exit /b
