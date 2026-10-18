@echo off
setlocal
set CLAUDE_FIFE_EXIT_WITH_CODE=1
pwsh -NoProfile -File "%~dp0claude-fife.ps1" %*
exit /b %ERRORLEVEL%
