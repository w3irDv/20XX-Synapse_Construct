@echo off
rem Double-click wrapper for Build-SynapseIso.ps1: runs it without changing the machine's execution policy.
rem Drag an ISO onto this file, or run:  Build-SynapseIso.cmd -SourceIso "C:\path\Melee.iso"
setlocal
if "%~1"=="" (
  echo Drag your Melee NTSC 1.02 ISO - vanilla or a supported mod, without Synapse - onto this file,
  echo or run it from a command prompt:
  echo   Build-SynapseIso.cmd -SourceIso "C:\path\to\Melee.iso"
  echo See README.md for every option.
  pause
  exit /b 1
)
set "ARGS=%*"
if exist "%~1" set "ARGS=-SourceIso "%~1""
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-SynapseIso.ps1" %ARGS%
set "RC=%ERRORLEVEL%"
echo.
echo Exit code %RC%.
if exist "%~1" pause
exit /b %RC%
