@echo off
rem Double-click this, or "Start Server.bat" in the project folder.
rem Listens on 127.0.0.1:8799. Tailscale Funnel on port 10000 forwards to it.
cd /d "%~dp0"

netstat -ano | findstr ":8799" | findstr "LISTENING" >nul
if not errorlevel 1 (
  echo The patch server is already running on port 8799.
  pause
  exit /b 0
)

if "%ENGINE_BUILDER_SECRET%"=="" (
  for /f "usebackq tokens=1,* delims==" %%A in (`findstr /i /b "secret=" "..\config\server.local.cfg"`) do set "ENGINE_BUILDER_SECRET=%%~B"
)
if "%ENGINE_BUILDER_SECRET%"=="" (
  echo No secret in config\server.local.cfg, and ENGINE_BUILDER_SECRET is not set.
  pause
  exit /b 2
)

set "PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not exist "%PY%" set "PY=python"

echo Starting the patch server on 127.0.0.1:8799. Close this window to stop it.
"%PY%" patch_server.py --port 8799 --host 127.0.0.1
echo The server stopped.
pause
