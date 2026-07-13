@echo off
setlocal enabledelayedexpansion
REM Nenjam Matrimony -- Android USB debugging setup
REM Forwards the phone's 127.0.0.1:3000 to this machine's 127.0.0.1:3000
REM over USB, via adb reverse, so Frontend/.env.dev's API_BASE_URL
REM (http://127.0.0.1:3000) always works regardless of Wi-Fi network.
REM See docs\development\android-usb-debugging.md for details.

where adb >nul 2>nul
if errorlevel 1 (
    echo [ERROR] adb was not found on PATH.
    echo         Install Android SDK Platform-Tools and add it to PATH, e.g.:
    echo         %%LOCALAPPDATA%%\Android\Sdk\platform-tools
    exit /b 1
)

echo Checking connected devices...
set DEVICE_COUNT=0
for /f "skip=1 tokens=1,2" %%A in ('adb devices') do (
    if not "%%A"=="" (
        if "%%B"=="device" (
            set /a DEVICE_COUNT+=1
            set DEVICE_SERIAL=%%A
        ) else if "%%B"=="unauthorized" (
            echo [ERROR] Device %%A is unauthorized. Check your phone screen
            echo         and accept the "Allow USB debugging?" prompt.
            exit /b 1
        ) else if "%%B"=="offline" (
            echo [ERROR] Device %%A is offline. Try: adb kill-server ^&^& adb start-server
            exit /b 1
        )
    )
)

if %DEVICE_COUNT%==0 (
    echo [ERROR] No authorized Android device found.
    echo         Connect your phone via USB, enable USB debugging, and accept
    echo         the debugging prompt on the device, then re-run this script.
    exit /b 1
)

if %DEVICE_COUNT% GTR 1 (
    echo [WARN] More than one device/emulator detected. Setting up reverse on all of them.
)

echo Setting up adb reverse tcp:3000 tcp:3000 ...
adb reverse tcp:3000 tcp:3000
if errorlevel 1 (
    echo [ERROR] adb reverse failed. See the output above.
    exit /b 1
)

echo.
echo [OK] adb reverse is active: phone's 127.0.0.1:3000 -^> this PC's 127.0.0.1:3000
echo [OK] Make sure the backend is running (pnpm start:dev from backend\), then run the Flutter app.
echo.
adb reverse --list

endlocal
