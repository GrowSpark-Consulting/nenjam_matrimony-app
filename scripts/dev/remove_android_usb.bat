@echo off
setlocal
REM Nenjam Matrimony -- removes all adb reverse port mappings.
REM See docs\development\android-usb-debugging.md for details.

where adb >nul 2>nul
if errorlevel 1 (
    echo [ERROR] adb was not found on PATH.
    echo         Install Android SDK Platform-Tools and add it to PATH, e.g.:
    echo         %%LOCALAPPDATA%%\Android\Sdk\platform-tools
    exit /b 1
)

echo Removing all adb reverse mappings...
adb reverse --remove-all
if errorlevel 1 (
    echo [ERROR] adb reverse --remove-all failed. See the output above.
    exit /b 1
)

echo [OK] All adb reverse mappings removed.

endlocal
