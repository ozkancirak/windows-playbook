@echo off

if /i "%~1"=="/justcontext" goto applyUserSetting

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



:applyUserSetting
reg add "HKCU\SOFTWARE\Classes\CLSID\{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" /v "System.IsPinnedToNameSpaceTree" /t REG_DWORD /d 0 /f > nul || exit /b 1

if /i "%~1"=="/justcontext" exit /b 0
if /i "%~1"=="/silent" exit /b 0

echo Finished, Network Navigation Pane is now disabled.
pause > nul
exit /b 0
