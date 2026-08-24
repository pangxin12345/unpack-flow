@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath C:\UF215\package.zip -DestinationPath C:\UF215\package -Force"
if errorlevel 1 exit /b %ERRORLEVEL%
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File C:\UF215\windows-native-run.ps1 > C:\UF215\windows-launcher.txt 2>&1
echo LAUNCHER_RC=%ERRORLEVEL%>> C:\UF215\windows-launcher.txt
exit /b %ERRORLEVEL%
