$root = $PSScriptRoot
if (Test-Path "$root\..\backend") {
    $root = (Get-Item "$root\..").FullName
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "       Launching Kivora Full System     " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. MySQL (:3306)
$port3306 = Get-NetTCPConnection -LocalPort 3306 -ErrorAction SilentlyContinue
if ($port3306) {
    Write-Host "[1/3] MySQL is already active on port 3306." -ForegroundColor Green
} else {
    Write-Host "[1/3] Starting MySQL from D:\xammp..." -ForegroundColor Yellow
    Start-Process -FilePath "D:\xammp\mysql\bin\mysqld.exe" -ArgumentList "--defaults-file=D:\xammp\mysql\bin\my.ini", "--standalone" -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

# 2. Backend (:8000)
$port8000 = Get-NetTCPConnection -LocalPort 8000 -ErrorAction SilentlyContinue
if ($port8000) {
    Write-Host "[2/3] Backend is already running on http://localhost:8000." -ForegroundColor Green
} else {
    Write-Host "[2/3] Starting Backend on http://localhost:8000..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$root\backend'; & '.\.venv\Scripts\uvicorn.exe' app.main:app --host 0.0.0.0 --port 8000 --reload"
}

# 3. Frontend (:3000)
$port3000 = Get-NetTCPConnection -LocalPort 3000 -ErrorAction SilentlyContinue
if ($port3000) {
    Write-Host "Freeing busy port 3000..." -ForegroundColor Magenta
    Get-Process -Id $port3000.OwningProcess -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
}

Write-Host "[3/3] Starting Frontend on Chrome :3000...`n" -ForegroundColor Green
Set-Location "$root\mobile"
flutter run -d chrome --web-port 3000
