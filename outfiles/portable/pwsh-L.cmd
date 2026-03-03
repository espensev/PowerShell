@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "_SCRIPT_DIR=%~dp0"
set "PSL_FORWARD_ARGS=%*"
set "POWERSHELL_PROFILE_DIRECTORY=%_SCRIPT_DIR%profile"
set "PSL_WT_ENABLED=1"
set "PSL_WT_EXE=D:\Development\DesktopApps\Console\terminal\publish\terminal-shell-portable\WindowsTerminal.exe"
set "PSL_WT_PROFILE_USER=PS-L"
set "PSL_WT_PROFILE_ADMIN=PS-L Admin"

if /I "%PSL_WT_INTERNAL%"=="1" (
    goto :run_pwsh
)

if /I "%PSL_WT_ENABLED%"=="1" (
    if not defined WT_SESSION (
        if exist "%PSL_WT_EXE%" (
            set "PSL_WT_PROFILE=%PSL_WT_PROFILE_USER%"
            net session >nul 2>&1
            if "%ERRORLEVEL%"=="0" set "PSL_WT_PROFILE=%[ADM]PS-L"
            start "" "%PSL_WT_EXE%" new-tab -p "%PSL_WT_PROFILE%" cmd.exe /c "set PSL_WT_INTERNAL=1&&\"%~f0\" !PSL_FORWARD_ARGS!"
            exit /b %ERRORLEVEL%
        )
    )
)

:run_pwsh
"%_SCRIPT_DIR%pwsh-L.exe" -NoLogo %*
