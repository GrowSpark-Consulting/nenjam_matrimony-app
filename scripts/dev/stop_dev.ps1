# Nenjam Matrimony -- tears down what start_dev.ps1 set up.
#
# Removes the tcp:3000 adb reverse mapping specifically (rather than
# --remove-all, which scripts/dev/remove_android_usb.bat still does for
# clearing every mapping) and stops whatever process is listening on
# port 3000 (the backend dev server started by start_dev.ps1).

$port = 3000

Write-Host "==> Removing adb reverse tcp:$port ..." -ForegroundColor Cyan
adb reverse --remove tcp:$port 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] adb reverse tcp:$port removed" -ForegroundColor Green
} else {
    Write-Host "[INFO] No active adb reverse tcp:$port mapping (nothing to remove)" -ForegroundColor Yellow
}

Write-Host "==> Stopping process listening on port $port ..." -ForegroundColor Cyan
try {
    $connections = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop
    $pids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($processId in $pids) {
        try {
            $proc = Get-Process -Id $processId -ErrorAction Stop
            Write-Host "[OK] Stopping $($proc.ProcessName) (PID $processId)" -ForegroundColor Green
            Stop-Process -Id $processId -Force
        } catch {
            Write-Host "[WARN] Could not stop PID $processId : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "[INFO] Nothing is listening on port $port" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
