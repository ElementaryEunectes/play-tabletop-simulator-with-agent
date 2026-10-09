@echo off
REM start.cmd - double-click THIS. Ordinary Windows users should not run the .ps1 directly.
REM
REM WHY THIS EXISTS
REM   * double-clicking a .ps1 opens Notepad (that is the default association), and
REM   * "Run with PowerShell" is blocked by the default execution policy (Restricted) and by the
REM     download marker (Zone.Identifier) on a file that came out of a zip.
REM   -ExecutionPolicy Bypass below is a COMMAND-LINE switch, so this works on a clean machine
REM   without changing any machine policy.
REM
REM ASCII ONLY on purpose: cmd.exe reads .cmd/.bat in the OEM code page, so Chinese text here
REM would print as mojibake. The friendly/prose part is printed by start-agent.ps1 (UTF-8 + BOM).
REM
REM WHICH PROFILE THIS PROJECT BOOTS WITH
REM   That is ONE line in start-agent.ps1: $ProjectDshProfile ('' = the harness default, `web`).
REM   Pass -DshProfile <name> here to override it for one run, e.g.
REM       start.cmd -DshProfile tts-agent
REM   This file forwards its arguments (%*), so the switch reaches the script unchanged.
REM   What a profile buys you (emptying the global instruction slot for this project only) and how
REM   to create/install one: tts\docs\INJECTION.md, section 4 plan A'.
REM
REM %~dp0 is this file's own folder (handles spaces and non-ASCII paths). pause keeps the window
REM open so an error is readable instead of flashing past.
setlocal

where dsh >nul 2>nul
if errorlevel 1 (
  echo.
  echo   [start.cmd] The 'dsh' command was not found on PATH.
  echo   Install Node.js, then run:   npm i -g @deepseek-ai/dsh
  echo   The full checklist is in README.md ^("What you need to run this"^).
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-agent.ps1" %*
if errorlevel 1 (
  echo.
  echo   [start.cmd] start-agent.ps1 exited with an error ^(see above^).
  pause
)
endlocal
