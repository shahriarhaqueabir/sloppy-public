@echo off
setlocal
title Sloppy installer
echo.
echo  Sloppy installer
echo  =================
echo.
set "SLOP_PS=pwsh"
where pwsh >nul 2>&1
if not errorlevel 1 goto :run
set "SLOP_PS=powershell"
where powershell >nul 2>&1
if not errorlevel 1 goto :run
echo Sloppy needs Windows PowerShell or PowerShell 7.
echo Install PowerShell 7 from https://aka.ms/powershell then re-run.
pause
exit /b 1

:run
%SLOP_PS% -NoProfile -ExecutionPolicy Bypass -Command ^
  "$i = irm https://raw.githubusercontent.com/shahriarhaqueabir/Sloppy/main/install.ps1; ^& ([scriptblock]::Create($i))"
if errorlevel 1 (
  echo Sloppy setup did not complete.
  pause
  exit /b 1
)
endlocal
