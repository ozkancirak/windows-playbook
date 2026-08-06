@echo off
set "script=%windir%\SystemRuntime\Scripts\ApplyNewUserConfiguration.ps1"

if not exist "%script%" (
    echo Script not found: "%script%"
    pause
    exit /b 1
)

powershell -ExecutionPolicy Bypass -NoProfile -File "%script%"
exit /b %errorlevel%
