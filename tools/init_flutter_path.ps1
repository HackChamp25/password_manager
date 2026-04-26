# Dot-source in PowerShell:  . .\tools\init_flutter_path.ps1
# Refreshes PATH from the registry (fixes stale terminals) and prepends Flutter Downloads layout if present.

$machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
$user = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machine;$user"

$bin = $null
$candidates = @(
  (Join-Path $env:USERPROFILE "Downloads\flutter_windows_3.41.7-stable\flutter\bin")
)
$root = Join-Path $env:USERPROFILE "Downloads"
if (Test-Path $root) {
  Get-ChildItem -Path $root -Directory -Filter "flutter_windows_*" -ErrorAction SilentlyContinue | ForEach-Object {
    $candidates += (Join-Path $_.FullName "flutter\bin")
  }
}
foreach ($c in $candidates) {
  if (Test-Path (Join-Path $c "flutter.bat")) { $bin = $c; break }
}
if ($null -ne $bin -and $env:Path -notlike "*$bin*") {
  $env:Path = "$bin;$env:Path"
}
Write-Host "OK. In PowerShell use:  where.exe flutter" -ForegroundColor Green
Write-Host "Not:                    where flutter   (that is Where-Object, not a search.)" -ForegroundColor Yellow
Write-Host "Then:  flutter --version" -ForegroundColor Green
