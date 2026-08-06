@echo off
setlocal EnableExtensions DisableDelayedExpansion
set indexConfPath="%windir%\SystemRuntime\Scripts\ConfigureSearchIndexing.cmd"

whoami /user | find /i "S-1-5-18" > nul 2>&1
if not errorlevel 1 goto main

set "RunAsTI_WaitForExit=1"
call "%windir%\SystemRuntime\Scripts\RunAsTI.cmd" "%~f0" %*
set "RunAsTI_ExitCode=%errorlevel%"
exit /b %RunAsTI_ExitCode%

:main
if not exist "%indexConfPath%" (
    echo The 'ConfigureSearchIndexing.cmd' script wasn't found in SystemRuntime.
    if /i not "%~1"=="/silent" pause
    exit /b 1
)
set "indexConf=call %indexConfPath%"

echo.
echo Disabling search indexing...
%indexConf% /stop || exit /b 1

powershell -NoP -NonI -ExecutionPolicy Bypass -File "%windir%\SystemRuntime\Scripts\verifySearchIndexing.ps1" -State Disabled || exit /b 1

if "%~1"=="/silent" exit /b 0
echo.
echo Search Indexing has been disabled.
echo Press any key to exit...
pause > nul
exit /b 0
