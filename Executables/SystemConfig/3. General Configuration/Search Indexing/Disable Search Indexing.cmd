@echo off
set indexConfPath="%windir%\SystemRuntime\Scripts\ConfigureSearchIndexing.cmd"

whoami /user | find /i "S-1-5-18" > nul 2>&1 || (
    call RunAsTI.cmd "%~f0" %*
    exit /b
)

if not exist "%indexConfPath%" (
    echo The 'ConfigureSearchIndexing.cmd' script wasn't found in SystemRuntime.
    pause
    exit /b 1
)
set "indexConf=call %indexConfPath%"


echo.
echo Disabling search indexing...
%indexConf% /stop

echo.
echo Search Indexing has been disabled.
echo Press any key to exit...
pause > nul
exit /b
