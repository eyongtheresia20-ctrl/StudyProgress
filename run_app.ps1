param(
    [ValidateSet("web", "android")]
    [string]$Target = "web",
    [int]$WebPort = 8085,
    [switch]$Rebuild
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackendDir = Join-Path $Root "backend"
$MobileDir = Join-Path $Root "mobile"
$PythonExe = Join-Path $BackendDir ".venv\Scripts\python.exe"
$UvicornExe = Join-Path $BackendDir ".venv\Scripts\uvicorn.exe"
$WebBuildDir = Join-Path $MobileDir "build\web"
$XamppMysqlStart = "D:\xammp\mysql_start.bat"

function Test-PortOpen {
    param([int]$Port)
    try {
        $client = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $Port)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

# 1. Ensure XAMPP MySQL (port 3306) is running
if (-not (Test-PortOpen -Port 3306)) {
    if (Test-Path $XamppMysqlStart) {
        Write-Host "Starting MySQL..." -ForegroundColor Cyan
        Start-Process -FilePath $XamppMysqlStart -WindowStyle Minimized | Out-Null
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-PortOpen -Port 3306) { break }
        }
    }
}

# 2. Ensure FastAPI Backend (port 8000) is running
if (-not (Test-PortOpen -Port 8000)) {
    Write-Host "Starting Backend API..." -ForegroundColor Cyan
    Start-Process powershell -ArgumentList @(
        "-NoExit",
        "-Command",
        "Set-Location '$BackendDir'; & '$UvicornExe' app.main:app --host 0.0.0.0 --port 8000 --reload"
    ) -WindowStyle Minimized | Out-Null
}

# 3. Android or Instant Web Launch
if ($Target -eq "android") {
    Set-Location $MobileDir
    flutter run
    exit $LASTEXITCODE
}

if ($Rebuild -or -not (Test-Path (Join-Path $WebBuildDir "index.html"))) {
    Write-Host "Building Flutter Web app (one-time)..." -ForegroundColor Cyan
    Set-Location $MobileDir
    flutter build web --no-wasm-dry-run
}

Write-Host "App is live at http://localhost:$WebPort (Press Ctrl+C to stop)" -ForegroundColor Green
Start-Job -ScriptBlock {
    param($Port)
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 300
        try {
            $client = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $Port)
            $client.Close()
            Start-Process "http://localhost:$Port"
            break
        } catch {}
    }
} -ArgumentList $WebPort | Out-Null

& $PythonExe $Root\serve_web.py
