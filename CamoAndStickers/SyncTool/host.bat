@echo off
rem Camo & Stickers: share your camo with the other players. Leave this window open.
cd /d "%~dp0"
set PORT=27777
set /p KEY="Password for friends (Enter = none): "
set ARGS=host --port %PORT% --folder "%~dp0..\Sync"
if not "%KEY%"=="" set ARGS=%ARGS% --key "%KEY%"
where py >nul 2>nul
if %errorlevel%==0 (py -3 camo_sync.py %ARGS%) else (python camo_sync.py %ARGS%)
pause
