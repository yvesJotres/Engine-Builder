@echo off
title Engine Builder - trigger value ladder
setlocal
cd /d "%~dp0"

set "PY="
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PY if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
if not defined PY if exist "C:\Program Files\Python312\python.exe" set "PY=C:\Program Files\Python312\python.exe"
if not defined PY if exist "C:\ProgramData\chocolatey\bin\python3.14.exe" set "PY=C:\ProgramData\chocolatey\bin\python3.14.exe"

if not defined PY (
    echo No working Python found.
    pause
    exit /b 2
)

"%PY%" "%~dp0gamepad_calibrate.py" --ladder %*
set "RESULT=%ERRORLEVEL%"

echo.
echo  Closing in 15 seconds. The numbers above are also in gamepad_calibration_result.txt
ping -n 16 127.0.0.1 > nul
exit /b %RESULT%
