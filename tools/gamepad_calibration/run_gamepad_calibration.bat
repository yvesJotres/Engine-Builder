@echo off
title Engine Builder - gamepad calibration
setlocal
cd /d "%~dp0"
set "SCRIPT=%~dp0gamepad_calibrate.py"
set "PY="

rem Pick a Python that actually runs. The py launcher and the chocolatey shim on this machine both point at
rem C:\Python314\python.exe, which is missing, so each candidate is tested with --version before it is trusted.
call :try_path "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
call :try_path "%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
call :try_path "C:\Program Files\Python312\python.exe"
call :try_path "C:\ProgramData\chocolatey\bin\python3.14.exe"
if not defined PY call :try_cmd py -3.12
if not defined PY call :try_cmd py -3.11
if not defined PY call :try_cmd python

if not defined PY (
    echo.
    echo  No working Python found.
    echo  Tried: %LOCALAPPDATA%\Programs\Python\Python312\python.exe, py -3.12, py -3.11, python.
    echo  Install Python 3 or edit the paths at the top of this file.
    echo.
    pause
    exit /b 2
)

echo using: %PY%
echo.
%PY% "%SCRIPT%" %*
set "RESULT=%ERRORLEVEL%"

echo.
echo  Closing in 6 seconds...
ping -n 7 127.0.0.1 > nul
exit /b %RESULT%

:try_path
if defined PY exit /b
if not exist %1 exit /b
%1 --version >nul 2>&1
if errorlevel 1 exit /b
set "PY=%1"
exit /b

:try_cmd
if defined PY exit /b
%* --version >nul 2>&1
if errorlevel 1 exit /b
set "PY=%*"
exit /b
