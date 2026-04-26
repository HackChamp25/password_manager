@echo off
REM Flutter Password Manager - Quick Setup Script for Windows

echo.
echo 🔐 Secure Password Manager - Flutter Setup
echo ===========================================
echo.

REM Check Flutter installation
echo ✓ Checking Flutter installation...
where flutter >nul 2>nul
if errorlevel 1 (
    echo ❌ Flutter not found. Please install Flutter first:
    echo    https://flutter.dev/docs/get-started/install
    pause
    exit /b 1
)

echo ✓ Flutter version:
flutter --version
echo.

REM Check Dart installation
echo ✓ Checking Dart installation...
where dart >nul 2>nul
if errorlevel 1 (
    echo ❌ Dart not found. Install Flutter to get Dart.
    pause
    exit /b 1
)

echo ✓ Checking connected devices...
flutter devices
echo.

echo ✓ Getting dependencies...
call flutter pub get

echo.
echo ✓ Running code analysis...
call flutter analyze

echo.
echo ===========================================
echo ✅ Setup complete!
echo.
echo To run the app:
echo.
echo   flutter run -d windows
echo.
echo To build for release:
echo.
echo   flutter build windows --release
echo.
echo ===========================================
echo.
pause
