@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-link65.ps1"
set "flashExitCode=%ERRORLEVEL%"

echo.
if not "%flashExitCode%"=="0" (
  echo Flashing did not complete. Read the message above before trying again.
)
pause
exit /b %flashExitCode%
