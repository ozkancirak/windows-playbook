@echo off
:: Change to match the setting name (e.g., Sleep, Indexing, etc.)
:: Change to 0 (Disabled) or 1 (Enabled/Minimal) etc

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

:: Update Registry (State and Path)

if not "%~1"=="/silent" call "%windir%\SystemRuntime\Scripts\ShowServiceWarning.cmd" %*

:main
:: check if the service exists
reg query "HKLM\SYSTEM\CurrentControlSet\Services\NVDisplay.ContainerLocalSystem" > nul 2>&1 || (
	if "%~1"=="/silent" exit /b
    echo The NVIDIA Display Container LS service does not exist, you cannot continue.
	echo You may not have NVIDIA drivers installed.
    echo]
    pause
    exit /b
)

call setSvc.cmd NVDisplay.ContainerLocalSystem 2
sc start NVDisplay.ContainerLocalSystem > nul 2>&1

if "%~1"=="/silent" exit /b

echo Finished, changes have been applied.
pause
exit /b