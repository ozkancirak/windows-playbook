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
echo Configuring minimal search indexing...
%indexConf% /stop || exit /b 1
%indexConf% /cleanpolicies || exit /b 1
%indexConf% /include "%programdata%\Microsoft\Windows\Start Menu\Programs" || exit /b 1
%indexConf% /include "%windir%\SystemConfig" || exit /b 1
%indexConf% /exclude "%systemdrive%\Users" || exit /b 1

reg add "HKLM\Software\Microsoft\Windows Search\Gather\Windows\SystemIndex" /v "RespectPowerModes" /t REG_DWORD /d 1 /f > nul || exit /b 1

%indexConf% /start || exit /b 1
reg add "HKLM\SOFTWARE\Microsoft\Windows Search" /v SetupCompletedSuccessfully /t REG_DWORD /d 0 /f > nul || exit /b 1

powershell -NoP -NonI -ExecutionPolicy Bypass -File "%windir%\SystemRuntime\Scripts\verifySearchIndexing.ps1" -State Minimal -RespectPowerModes 1 || exit /b 1

if "%~1"=="/silent" exit /b 0
echo.
echo Minimal Search Indexing has been configured.
echo Press any key to exit...
pause
exit /b 0
