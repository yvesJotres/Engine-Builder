@echo off
rem Engine Builder's patch server, on its own port (8799). Flatframe uses 8787 and 8788, so these never clash.
rem The secret comes from the ENGINE_BUILDER_SECRET environment variable and is never written to a file.
rem Set it once for your user account:  setx ENGINE_BUILDER_SECRET "<the secret from config\server.local.cfg>"
cd /d "%~dp0"
if "%ENGINE_BUILDER_SECRET%"=="" (
  echo ENGINE_BUILDER_SECRET is not set. Refusing to start without a secret.
  exit /b 2
)
python patch_server.py --port 8799 --host 127.0.0.1
