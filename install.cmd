@echo off
setlocal
title Sloppy installer
echo.
echo  Sloppy installer
echo  =================
echo.
where pwsh >nul 2>&1
if errorlevel 1 (
  echo Sloppy needs PowerShell 7.6 or newer.
  echo Install it from https://aka.ms/powershell then re-run.
  pause
  exit /b 1
)

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$i = irm https://raw.githubusercontent.com/shahriarhaqueabir/Sloppy/main/install.ps1; ^& ([scriptblock]::Create($i))"
if errorlevel 1 (
  echo Sloppy setup did not complete.
  pause
  exit /b 1
)
endlocal
