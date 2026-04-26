@echo off
REM Password Manager: FastAPI + Flutter (Edge when Windows desktop toolchain is missing)
cd /d "%~dp0"
call "%~dp0tools\flutter_path.bat"
where.exe flutter >nul 2>&1
if errorlevel 1 (
  echo Could not find flutter.bat. Add ...\flutter\bin to User PATH or keep SDK under Downloads\flutter_windows_*
  pause
  exit /b 1
)

set "PYTHONPATH=%~dp0backend"
echo Starting FastAPI on http://127.0.0.1:8000 ...
start "Password Manager Backend" cmd /k "cd /d %~dp0 && set PYTHONPATH=%~dp0backend && python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000"
timeout /t 3 /nobreak > nul

echo.
echo Choose target: Windows desktop needs "Desktop development with C++" in Visual Studio.
echo Using Microsoft Edge (no extra build tools). Log in after the window opens.
echo.
cd flutter
flutter run -d edge
pause
