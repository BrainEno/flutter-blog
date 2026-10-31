@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_android.ps1" %*
set "result=%errorlevel%"
if not "%result%"=="0" (
  echo.
  echo Android debug did not start. See the error above and README.md.
  if not defined CI pause
)
exit /b %result%
