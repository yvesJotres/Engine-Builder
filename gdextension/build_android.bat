@echo off
rem Builds the engine_sim extension for Android arm64 with CMake, Ninja and the NDK. Usage: build_android.bat [template_debug|template_release]
rem The NDK lives in D:\Android\Sdk (sdkmanager --sdk_root=D:\Android\Sdk --install "ndk;23.2.8568313"); override with ANDROID_NDK_ROOT.
set TARGET=%1
if "%TARGET%"=="" set TARGET=template_release
set BT=RelWithDebInfo
if "%TARGET%"=="template_release" set BT=Release
if "%ANDROID_NDK_ROOT%"=="" set ANDROID_NDK_ROOT=D:\Android\Sdk\ndk\23.2.8568313
set PATH=%PATH%;C:\Program Files\CMake\bin;%LOCALAPPDATA%\Programs\Python\Python312\Scripts
cd /d "%~dp0"
cmake -S . -B build\android-%BT% -G Ninja -DCMAKE_BUILD_TYPE=%BT% ^
  -DCMAKE_TOOLCHAIN_FILE="%ANDROID_NDK_ROOT%\build\cmake\android.toolchain.cmake" ^
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_static ^
  -DES_TARGET_OVERRIDE=%TARGET%
if errorlevel 1 exit /b 1
cmake --build build\android-%BT%
