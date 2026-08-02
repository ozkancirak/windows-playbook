@echo off
set "script=%windir%\SystemRuntime\Scripts\ScriptWrappers\DisablePowerSaving.ps1"

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

if not exist "%script%" (
    echo Script not found.
    echo "%script%"
    pause
    exit /b 1
)


powershell -EP Bypass -NoP -File "%script%" %*

if "%~1"=="/silent" exit /b

echo.
echo Power Saving has been disabled.
echo Press any key to exit...
pause > nul
exit /b
