@echo off
REM Standalone desktop app: vault and crypto run inside Flutter (no Python required).
cd /d "%~dp0"
call "%~dp0tools\flutter_path.bat"
where.exe flutter >nul 2>&1
if errorlevel 1 (
  echo Add Flutter to PATH or use tools\flutter_path.bat
  pause
  exit /b 1
)
cd flutter
echo.
echo Build/run Windows desktop. Install "Desktop development with C++" in Visual Studio if build fails.
echo.
flutter run -d windows
pause
