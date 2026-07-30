@echo off
echo Instalando modulo ps2exe (si no esta instalado)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "if (-not (Get-Module -ListAvailable -Name ps2exe)) { Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber }"

echo.
echo Desbloqueando y cargando el modulo...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Get-Module -ListAvailable -Name ps2exe | ForEach-Object { Get-ChildItem $_.ModuleBase -Recurse | Unblock-File }; Import-Module ps2exe -Force"

echo.
echo Generando FARMASOFT.exe...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Import-Module ps2exe -Force; Invoke-ps2exe -inputFile '%~dp0GestorRutasDNS.ps1' -outputFile '%~dp0FARMASOFT.exe' -noConsole -title 'FARMASOFT' -requireAdmin"

echo.
echo Listo. Revisa la carpeta: FARMASOFT.exe
pause
