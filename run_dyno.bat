@echo off
setlocal
cd /d "%~dp0"
if "%~1"=="" (
  echo Usage: run_dyno.bat ^<preset_id^> [--path native^|gd] [--name NAME] [key=value ...]
  echo Example: run_dyno.bat honda_cbr250rr_2020
  pause
  exit /b 1
)
python tools\diagnostics\run_dyno.py %*
set RC=%ERRORLEVEL%
echo.
if %RC%==0 (echo Done.) else (echo The run failed with code %RC%.)
pause
exit /b %RC%
