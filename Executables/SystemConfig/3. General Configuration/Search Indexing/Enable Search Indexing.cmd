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
echo Enabling full search indexing...
%indexConf% /stop || exit /b 1
%indexConf% /cleanpolicies || exit /b 1
%indexConf% /include "%programdata%\Microsoft\Windows\Start Menu\Programs" || exit /b 1
%indexConf% /include "%windir%\SystemConfig" || exit /b 1
%indexConf% /include "%systemdrive%\Users" || exit /b 1

:: Add default user exclusions
for /f "usebackq delims=" %%a in (`dir /b /a:d "%SystemDrive%\Users"`) do (
	for %%z in (
		"AppData"
		"MicrosoftEdgeBackups"
	) do (
		if exist "%SystemDrive%\Users\%%~a\%%~z" (
			%indexConf% /exclude "%SystemDrive%\Users\%%~a\%%~z" || exit /b 1
		)
	)
)

%indexConf% /start || exit /b 1

set "respectPowerModes=1"
if "%~1"=="/silent" goto applyRespectPowerModes
echo.
:: Respect Power Settings when Search Indexing to prevent performance loss during gaming or battery drain
choice /c:yn /n /m "Would you like to have indexing disable itself when on battery or gaming? [Y/N] "
if %errorlevel%==1 set "respectPowerModes=1"
if %errorlevel%==2 set "respectPowerModes=0"

:applyRespectPowerModes
reg add "HKLM\Software\Microsoft\Windows Search\Gather\Windows\SystemIndex" /v "RespectPowerModes" /t REG_DWORD /d %respectPowerModes% /f > nul || exit /b 1
reg add "HKLM\SOFTWARE\Microsoft\Windows Search" /v SetupCompletedSuccessfully /t REG_DWORD /d 0 /f > nul || exit /b 1
powershell -NoP -NonI -ExecutionPolicy Bypass -File "%windir%\SystemRuntime\Scripts\verifySearchIndexing.ps1" -State Enabled -RespectPowerModes %respectPowerModes% || exit /b 1

if "%~1"=="/silent" exit /b 0
echo.
echo Full Search Indexing has been enabled.
echo Press any key to exit...
pause > nul
exit /b 0
