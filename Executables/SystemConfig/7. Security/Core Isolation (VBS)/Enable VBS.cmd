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

:: End of state and path update

reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /t REG_DWORD /v Enabled /d "1" /f > nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /t REG_DWORD /v EnableVirtualizationBasedSecurity /d "1" /f > nul

echo Changes applied successfully.
echo Press any key to exit...
pause > nul
exit /b