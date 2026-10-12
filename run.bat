@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Ark Resmon

for /f "tokens=2 delims=:" %%P in ('chcp') do set "OLDCP=%%P"
set "OLDCP=%OLDCP: =%"
echo Console code page: %OLDCP%
if not "%OLDCP%"=="65001" (
    chcp 65001 >nul
    if errorlevel 1 (
        echo Could not switch the console to UTF-8. Continuing.
    ) else (
        echo Switched console to UTF-8 code page 65001.
    )
) else (
    echo Console is already UTF-8 code page 65001.
)

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0monitor.ps1"
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
    echo.
    echo Monitor exited with code %ERR%.
    pause
)
endlocal & exit /b %ERR%
