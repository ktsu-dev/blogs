@echo off
echo Rebuilding blog index...
powershell -ExecutionPolicy Bypass -File "%~dp0Rebuild-BlogIndex.ps1"
pause 