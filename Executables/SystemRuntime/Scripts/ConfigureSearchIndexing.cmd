@echo off
setlocal EnableExtensions DisableDelayedExpansion

fltmc > nul 2>&1 || (echo You must run this script as admin. & exit /b 1)
set ___settings=call "%windir%\SystemRuntime\Scripts\ConfigureSettingsPages.cmd"


:: Check args
set ___policy=
if "%~1"=="" goto help
echo %1 | find "clude" > nul && (
    if "%~2"=="" goto help
    set ___policy=true
)

:: /include & /exclude
if defined ___policy goto runPolicy

if "%~1"=="/cleanpolicies" (
    echo Cleaning policies...
    for %%a in (
        "HKLM\Software\Policies\Microsoft\Windows\Windows Search\DefaultExcludedPaths"
        "HKLM\Software\Policies\Microsoft\Windows\Windows Search\DefaultIndexedPaths"
        "HKLM\Software\Microsoft\Windows Search\CurrentPolicies\DefaultExcludedPaths"
        "HKLM\Software\Microsoft\Windows Search\CurrentPolicies\DefaultIndexedPaths"
    ) do (
        reg delete %%a /f > nul 2>&1
        reg query %%a > nul 2>&1 && exit /b 1
        reg add %%a /f > nul || exit /b 1
    )
    exit /b 0
)

if "%~1"=="/start" (
    echo Starting the indexer...
    sc config WSearch start= delayed-auto > nul || exit /b 1
    sc start WSearch > nul 2>&1
    powershell -NoP -NonI -C "try { $service=Get-Service -Name 'WSearch' -ErrorAction Stop; if ($service.Status -ne 'Running') { $service.WaitForStatus('Running',[TimeSpan]::FromSeconds(30)) }; if ($service.Status -ne 'Running') { exit 1 } } catch { exit 1 }" || exit /b 1

    %___settings% /unhide cortana-windowssearch

    echo Updating policy... ^(this might take a moment^)
    gpupdate > nul 2>&1
    exit /b 0
)

if "%~1"=="/stop" (
    echo Stopping the indexer...

    %___settings% /hide cortana-windowssearch

    rem Kill the search index Control Panel pane
    powershell -NoP -NonI -C "Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'srchadmin[.]dll' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
    
    sc config WSearch start= disabled > nul || exit /b 1
    sc stop WSearch > nul 2>&1
    powershell -NoP -NonI -C "try { $service=Get-Service -Name 'WSearch' -ErrorAction Stop; if ($service.Status -ne 'Stopped') { $service.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30)) }; if ($service.Status -ne 'Stopped') { exit 1 } } catch { exit 1 }" || exit /b 1
    exit /b 0
)

exit /b 1


:runPolicy
    call :addIndexPath %~1 "%~2"
    exit /b %errorlevel%



:help
    echo You must use one (not in combination)
    echo -------------------------------------
    echo /include [full folder path]
    echo /exclude [full folder path]
    echo /cleanpolicies
    echo /start
    echo /stop
    exit /b 1


:addIndexPath
    echo Configuring indexer path...
    set policy=DefaultIndexedPaths
    if "%~1"=="/exclude" set policy=DefaultExcludedPaths

    set "searchPath1=%~2"
    set "searchPath=file:///%searchPath1%\*"
    reg add "HKLM\Software\Policies\Microsoft\Windows\Windows Search\%policy%" /v "%searchPath%" /t REG_SZ /d "%searchPath%" /f > nul || exit /b 1
    reg add "HKLM\Software\Microsoft\Windows Search\CurrentPolicies\%policy%" /v "%searchPath%" /t REG_SZ /d "%searchPath%" /f > nul || exit /b 1
    exit /b 0


:cleanPolicies
    for %%a in (
        "HKLM\Software\Policies\Microsoft\Windows\Windows Search\DefaultExcludedPaths"
        "HKLM\Software\Policies\Microsoft\Windows\Windows Search\DefaultIndexedPaths"
        "HKLM\Software\Microsoft\Windows Search\CurrentPolicies\DefaultExcludedPaths"
        "HKLM\Software\Microsoft\Windows Search\CurrentPolicies\DefaultIndexedPaths"
    ) do (
        reg delete %%a /f > nul 2>&1
        reg add %%a /f > nul 2>&1
    )
    exit /b
