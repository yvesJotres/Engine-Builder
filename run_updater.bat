@echo off
REM Engine Builder - Standalone Patch Updater Runner
REM Runs the GDScript updater to check and apply patches

setlocal

set "GODOT_PATH=D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
set "PROJECT_ROOT=D:\Projects\Engine Builder"

echo ==========================================
echo Engine Builder - Patch Updater
echo ==========================================
echo.

if not exist "%GODOT_PATH%" (
    echo ERROR: Godot not found at "%GODOT_PATH%"
    pause
    exit /b 1
)

echo Checking for updates...
"%GODOT_PATH%" --headless --script "res://scripts/platform/updates/standalone_updater.gd" --path "%PROJECT_ROOT%"

set EXIT_CODE=%errorlevel%

echo.
if %EXIT_CODE%==0 (
    echo SUCCESS: Patch downloaded and applied!
    echo Restart Engine Builder to load the update.
) else if %EXIT_CODE%==1 (
    echo ERROR: Update check failed (network, timeout, or verification)
) else if %EXIT_CODE%==2 (
    echo INFO: No delta patch available for your version.
    echo Download the full installer from the website.
) else (
    echo UNKNOWN ERROR (code %EXIT_CODE%)
)

echo.
pause
exit /b %EXIT_CODE%