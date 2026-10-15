@echo off
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0tool\build-apk.ps1"
pause
