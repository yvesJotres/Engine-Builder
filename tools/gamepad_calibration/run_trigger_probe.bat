@echo off
title Engine Builder - throttle trigger probe
setlocal
cd /d "%~dp0..\.."
set "GODOT=D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
set "OUT=%~dp0..\..\tools\diagnostics\throttle_live.txt"

rem a goto, not an if-block: the ")" in "Program Files (x86)" would close a parenthesised block early
if not exist "%GODOT%" goto nogodot

if exist "%OUT%" del /q "%OUT%"

echo ============================================================
echo  Trigger probe
echo ============================================================
echo  A game window opens and records for 45 seconds.
echo.
echo    1. squeeze RIGHT TRIGGER all the way in, hold 2 s, release
echo    2. squeeze LEFT TRIGGER  all the way in, hold 2 s, release
echo    3. press A, RB, LB, Y once each  (optional)
echo.
echo  You can close the window early once you have done 1 and 2.
echo ============================================================
echo.

start "" "%GODOT%" --path "%CD%" -s res://tools/diagnostics/probe_throttle_live.gd

echo waiting for the trace...
:wait
ping -n 3 127.0.0.1 > nul
if not exist "%OUT%" goto wait
findstr /c:"END" "%OUT%" > nul 2>&1
if errorlevel 1 (
    ping -n 3 127.0.0.1 > nul
    findstr /c:"END" "%OUT%" > nul 2>&1
    if errorlevel 1 (
        echo   still recording, one moment...
        goto wait
    )
)

echo.
echo ================= trace =================
type "%OUT%"
echo =========================================
echo.
echo  Closing in 15 seconds.
ping -n 16 127.0.0.1 > nul
exit /b 0

:nogodot
echo Godot not found at:
echo   "%GODOT%"
echo Edit the GODOT line at the top of this file.
pause
exit /b 2
