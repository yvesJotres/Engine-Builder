@echo off
REM Engine Builder - Build Script
REM Builds Windows installer, Android APK, or both

setlocal enabledelayedexpansion

REM ==========================================
REM Configuration - Edit these paths if needed
REM ==========================================
set "GODOT_PATH=D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
set "NSIS_PATH=C:\Program Files (x86)\NSIS\makensis.exe"
for /f "tokens=2 delims==" %%a in ('findstr /b "config/version=" project.godot') do set "PRODUCT_VERSION=%%~a"
set "PRODUCT_VERSION=%PRODUCT_VERSION:\"=%"

echo ==========================================
echo Engine Builder - Build Menu
echo ==========================================
echo.
echo [1] Build Windows Installer (NSIS)
echo [2] Build Android APK
echo [3] Build Both (Windows + Android)
echo [4] Install NSIS (via Chocolatey)
echo [5] Exit
echo.

:CHOICE
set /p CHOICE="Enter choice [1-5]: "

if "%CHOICE%"=="1" goto BUILD_WINDOWS
if "%CHOICE%"=="2" goto BUILD_ANDROID
if "%CHOICE%"=="3" goto BUILD_BOTH
if "%CHOICE%"=="4" goto INSTALL_NSIS
if "%CHOICE%"=="5" goto EXIT

echo Invalid choice. Please enter 1, 2, 3, 4, or 5.
goto CHOICE

:BUILD_WINDOWS
echo.
echo ==========================================
echo Building Windows Installer...
echo ==========================================
echo.
call :CHECK_GODOT
call :EXPORT_WINDOWS
call :BUILD_NSIS_INSTALLER
echo.
echo Windows installer build complete!
echo Output: build\installer\EngineBuilder_Setup_%PRODUCT_VERSION%.exe
goto END

:BUILD_ANDROID
echo.
echo ==========================================
echo Building Android APK...
echo ==========================================
echo.
call :CHECK_GODOT
call :EXPORT_ANDROID
echo.
echo Android APK build complete!
echo Output: build\android\EngineBuilder.apk
goto END

:BUILD_BOTH
echo.
echo ==========================================
echo Building Windows Installer AND Android APK...
echo ==========================================
echo.
call :CHECK_GODOT
call :EXPORT_WINDOWS
call :BUILD_NSIS_INSTALLER
call :EXPORT_ANDROID
echo.
echo Both builds complete!
echo Windows: build\installer\EngineBuilder_Setup_%PRODUCT_VERSION%.exe
echo Android: build\android\EngineBuilder.apk
goto END

:INSTALL_NSIS
echo.
echo Installing NSIS via Chocolatey...
choco install nsis -y
if %errorlevel% neq 0 (
    echo ERROR: Failed to install NSIS
    echo Run as Administrator or install manually from https://nsis.sourceforge.io/
) else (
    echo NSIS installed successfully!
    echo Restart this script to use it.
)
goto END

:CHECK_GODOT
if not exist "%GODOT_PATH%" (
    echo ERROR: Godot not found at "%GODOT_PATH%"
    echo Edit GODOT_PATH in this script or add Godot to PATH
    exit /b 1
)
echo Godot found: %GODOT_PATH%
exit /b 0

:EXPORT_WINDOWS
echo Exporting Windows Desktop...
"%GODOT_PATH%" --headless --export-release "Windows Desktop" build/windows/EngineBuilder.exe
if %errorlevel% neq 0 (
    echo ERROR: Windows export failed
    exit /b 1
)
echo Windows export successful
exit /b 0

:EXPORT_ANDROID
echo Exporting Android...
"%GODOT_PATH%" --headless --export-release "Android" build/android/EngineBuilder.apk
if %errorlevel% neq 0 (
    echo ERROR: Android export failed
    exit /b 1
)
echo Android export successful
exit /b 0

:BUILD_NSIS_INSTALLER
echo Building NSIS installer...
if not exist "%NSIS_PATH%" (
    echo WARNING: NSIS (makensis) not found at "%NSIS_PATH%"
    echo Select option 4 to install via Chocolatey, or install manually from https://nsis.sourceforge.io/
    echo Skipping installer build...
    exit /b 0
)
cd /d "%~dp0installer"
"%NSIS_PATH%" /DPRODUCT_VERSION=%PRODUCT_VERSION% installer.nsi
if %errorlevel% neq 0 (
    echo ERROR: NSIS build failed
    exit /b 1
)
cd /d "%~dp0"
echo NSIS installer build successful
exit /b 0

:EXIT
echo.
echo Build cancelled.
goto END

:END
echo.
echo ==========================================
pause
