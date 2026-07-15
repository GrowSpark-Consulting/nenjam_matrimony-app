# Nenjam Matrimony -- one-command USB dev startup.
#
# Starts the NestJS backend, waits for it to actually be listening on
# 127.0.0.1:3000, then wires up `adb reverse` so a physical Android phone
# connected over USB can reach it at http://127.0.0.1:3000 -- the same
# address Frontend/.env.dev already points at. No Wi-Fi/LAN IP involved.
#
# See docs/development/android-usb-debugging.md for the manual-step
# fallback and troubleshooting.

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$backendDir = Join-Path $repoRoot 'backend'
$setupUsbScript = Join-Path $PSScriptRoot 'setup_android_usb.bat'
$port = 3000
$portTimeoutSeconds = 60

function Write-Step($message) {
    Write-Host ""
    Write-Host "==> $message" -ForegroundColor Cyan
}

function Test-PortOpen([string]$hostName, [int]$portNumber) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $task = $client.ConnectAsync($hostName, $portNumber)
        $completed = $task.Wait(500)
        $isOpen = $completed -and $client.Connected
        $client.Close()
        return $isOpen
    } catch {
        return $false
    }
}

# ─── 1. Start the backend in its own window so logs stay visible ──────────
Write-Step "Starting backend (pnpm start:dev) in a new window..."
Start-Process powershell -ArgumentList @(
    '-NoExit',
    '-Command',
    "Set-Location '$backendDir'; pnpm start:dev"
) | Out-Null

# ─── 2. Wait until something is actually listening on port 3000 ───────────
Write-Step "Waiting for backend to listen on 127.0.0.1:$port (timeout ${portTimeoutSeconds}s)..."
$elapsed = 0
$backendUp = $false
while ($elapsed -lt $portTimeoutSeconds) {
    if (Test-PortOpen '127.0.0.1' $port) {
        $backendUp = $true
        break
    }
    Start-Sleep -Seconds 1
    $elapsed++
    Write-Host "." -NoNewline
}
Write-Host ""

if (-not $backendUp) {
    Write-Host "[FAIL] Backend did not start listening on port $port within ${portTimeoutSeconds}s." -ForegroundColor Red
    Write-Host "       Check the backend window for errors (missing .env, DB not running, etc)." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Backend is listening on 127.0.0.1:$port" -ForegroundColor Green

# ─── 3. Device check + adb reverse (reuses the existing setup script) ─────
Write-Step "Checking device and setting up adb reverse..."
& $setupUsbScript
$adbExitCode = $LASTEXITCODE

if ($adbExitCode -ne 0) {
    Write-Host "[FAIL] adb reverse setup failed (see output above)." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] adb reverse tcp:$port tcp:$port is active" -ForegroundColor Green

# ─── 4. End-to-end confirmation via the health endpoint ───────────────────
Write-Step "Verifying backend health endpoint..."
try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -TimeoutSec 5 -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "[OK] GET /health -> 200 $($response.Content)" -ForegroundColor Green
    } else {
        Write-Host "[WARN] GET /health -> $($response.StatusCode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[FAIL] GET /health did not respond: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=================================================" -ForegroundColor Green
Write-Host " Ready. Backend + adb reverse are both up."       -ForegroundColor Green
Write-Host " Run the Flutter app now (it talks to http://127.0.0.1:$port)." -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green
