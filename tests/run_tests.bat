@echo off
rem Runs cadence's offline tests. Double-click it, or run it from any folder.
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo Setting up the test environment. This only happens once.
    python -m venv .venv || goto :no_python
    ".venv\Scripts\python.exe" -m pip install -r requirements.txt || goto :failed_setup
    echo.
)

".venv\Scripts\python.exe" run.py
if errorlevel 1 (
    echo.
    echo Some tests FAILED. Scroll up to see which.
) else (
    echo.
    echo All tests passed.
)
echo.
pause
exit /b

:no_python
echo Python 3.12 wasn't found. Install it from python.org, then run this again.
pause
exit /b 1

:failed_setup
echo Installing the test requirements failed. Check your internet connection and run this again.
pause
exit /b 1
