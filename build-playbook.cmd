@echo off
setlocal
pushd "%~dp0" || exit /b 1
echo Building Playbook...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-playbook.ps1" -ReplaceOldPlaybook -DontOpenPbLocation
set "buildExit=%errorlevel%"
if not "%buildExit%"=="0" (
    if "%*"=="" pause
)
popd
exit /b %buildExit%
