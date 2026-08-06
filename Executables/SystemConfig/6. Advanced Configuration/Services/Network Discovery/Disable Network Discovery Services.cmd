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

:: Unpin 'Network' from Explorer sidebar
call "%windir%\SystemConfig\3. General Configuration\File Sharing\Network Navigation Pane\Disable Network Navigation Pane (default).cmd" /justcontext > nul

call setSvc.cmd fdPHost 4
call setSvc.cmd FDResPub 4
call setSvc.cmd lmhosts 4
call setSvc.cmd SSDPSRV 4
if "%~1"=="/silent" exit /b

echo Finished, please reboot your device for changes to apply.
pause
exit /b
