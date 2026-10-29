@echo off
chcp 65001 >nul
cd /d "%~dp0"
where pyw >nul 2>nul
if %errorlevel%==0 (start "" pyw -3 "%~dp0CamoPanel.pyw" & exit /b)
where pythonw >nul 2>nul
if %errorlevel%==0 (start "" pythonw "%~dp0CamoPanel.pyw" & exit /b)
echo Python не найден. Установите Python 3 с python.org (отметьте "Add python.exe to PATH") и запустите снова.
pause
