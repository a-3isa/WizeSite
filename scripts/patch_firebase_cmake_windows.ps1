# Patches Firebase C++ SDK CMakeLists.txt for Windows so it works with CMake 3.5+.
# Run this if you see: "Compatibility with CMake < 3.5 has been removed"
# After "flutter clean", run: .\scripts\patch_firebase_cmake_windows.ps1

$baseDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cmakePath = Join-Path $baseDir "build\windows\x64\extracted\firebase_cpp_sdk_windows\CMakeLists.txt"

if (-not (Test-Path $cmakePath)) {
    Write-Host "Firebase SDK CMake file not found. Run 'flutter build windows' or 'flutter run -d windows' once (it may fail), then run this script again." -ForegroundColor Yellow
    exit 1
}

$content = Get-Content $cmakePath -Raw
if ($content -match 'cmake_minimum_required\(VERSION 3\.1\)') {
    $content = $content -replace 'cmake_minimum_required\(VERSION 3\.1\)', 'cmake_minimum_required(VERSION 3.5)'
    Set-Content $cmakePath -Value $content -NoNewline
    Write-Host "Patched $cmakePath (3.1 -> 3.5). You can run 'flutter run -d windows' again." -ForegroundColor Green
} else {
    Write-Host "File already patched or format changed. No change made." -ForegroundColor Gray
}
