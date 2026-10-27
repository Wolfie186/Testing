@echo off
rem Camo & Stickers: sync camo with the host. Leave this window open.
cd /d "%~dp0"
set /p HOST="Host IP (e.g. 26.12.34.56 or 192.168.1.10): "
set /p KEY="Password (Enter = none): "
set ARGS=join %HOST% --folder "%~dp0..\Sync"
if not "%KEY%"=="" set ARGS=%ARGS% --key "%KEY%"
where py >nul 2>nul
if %errorlevel%==0 (py -3 camo_sync.py %ARGS%) else (python camo_sync.py %ARGS%)
pause
