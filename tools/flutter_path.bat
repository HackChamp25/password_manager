@echo off
REM Prepend Flutter SDK "bin" to PATH (this cmd session only). Safe to CALL from run.bat.
if exist "%USERPROFILE%\Downloads\flutter_windows_3.41.7-stable\flutter\bin\flutter.bat" (
  set "PATH=%USERPROFILE%\Downloads\flutter_windows_3.41.7-stable\flutter\bin;%PATH%"
  exit /b 0
)
for /d %%D in ("%USERPROFILE%\Downloads\flutter_windows_*") do (
  if exist "%%~D\flutter\bin\flutter.bat" (
    set "PATH=%%~D\flutter\bin;%PATH%"
    exit /b 0
  )
)
exit /b 0
