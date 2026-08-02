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
echo Configuring minimal search indexing...
%indexConf% /stop
%indexConf% /cleanpolicies
%indexConf% /include "%programdata%\Microsoft\Windows\Start Menu\Programs"
%indexConf% /include "%windir%\SystemConfig"
%indexConf% /exclude "%systemdrive%\Users"

reg add "HKLM\Software\Microsoft\Windows Search\Gather\Windows\SystemIndex" /v "RespectPowerModes" /t REG_DWORD /d 1 /f > nul

%indexConf% /start
reg add "HKLM\SOFTWARE\Microsoft\Windows Search" /v SetupCompletedSuccessfully /t REG_DWORD /d 0 /f > nul

if "%~1"=="/silent" exit /b

echo.
echo Minimal Search Indexing has been configured.
echo Press any key to exit...
pause
exit /b
