@echo off
rem ANYK visszatoltese az uj gepen. A legujabb ANYK-mentes-*.zip-et veszi a script mellol.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ANYK-Atkoltozes.ps1" -Visszatoltes
pause
