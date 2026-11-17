@echo off
title Kivora Launcher
set "ROOT=%~dp0"
if exist "%ROOT%..\backend" set "ROOT=%ROOT%..\"

echo ========================================
echo   Launching Kivora System
echo ========================================

:: 1. Check & start MySQL (port 3306)
echo [1/3] Checking MySQL database (:3306)...
netstat -aon | findstr :3306 | findstr LISTENING >nul 2>&1
if errorlevel 1 (
    echo Starting MySQL from D:\xammp...
    start "Kivora MySQL" /min cmd /c "cd /d D:\xammp && mysql\bin\mysqld.exe --defaults-file=mysql\bin\my.ini --standalone"
    timeout /t 2 /nobreak >nul
) else (
    echo MySQL is already active on port 3306.
)

:: 2. Check & start Backend (port 8000)
echo [2/3] Checking Backend (FastAPI :8000)...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr :8000 ^| findstr LISTENING') do (
    echo Backend is already active on port 8000.
    goto :START_FRONTEND
)
start "Kivora Backend" cmd /k "cd /d "%ROOT%backend" && .venv\Scripts\uvicorn.exe app.main:app --host 0.0.0.0 --port 8000 --reload"

:START_FRONTEND
:: 3. Check & start Frontend (port 3000)
echo [3/3] Preparing Frontend (Flutter Web :3000)...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr :3000 ^| findstr LISTENING') do (
    echo Freeing port 3000 (killing PID %%a)...
    taskkill /F /PID %%a >nul 2>&1
)

cd /d "%ROOT%mobile"
flutter run -d chrome --web-port 3000
