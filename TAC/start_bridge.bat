@echo off
rem Triune LLM Bridge Launcher Script (Windows)
setlocal

cd /d "%~dp0"

where python >nul 2>nul
if %ERRORLEVEL% equ 0 (
    python triune_llm_bridge.py %*
    goto :eof
)

where py >nul 2>nul
if %ERRORLEVEL% equ 0 (
    py triune_llm_bridge.py %*
    goto :eof
)

echo [ERROR] Python 3 was not found in PATH. Please install Python 3.
pause
