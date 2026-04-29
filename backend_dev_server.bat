@echo off
REM Optional: run the old Python FastAPI + same vault file format (dev / migration testing only).
set "PYTHONPATH=%~dp0backend"
if not defined PM_API_PORT set "PM_API_PORT=18080"
cd /d "%~dp0"
python -m uvicorn app.main:app --reload --reload-dir "%~dp0backend" --host 127.0.0.1 --port %PM_API_PORT%
pause
