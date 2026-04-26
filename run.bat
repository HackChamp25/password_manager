@echo off
REM Windows launcher script for Password Manager (Backend + Frontend)
echo Starting FastAPI backend...
start "Password Manager Backend" uvicorn src.api.main:app --reload --host 127.0.0.1 --port 8000
timeout /t 3 /nobreak > nul
echo Starting Flutter frontend...
cd flutter
flutter run -d windows
pause

