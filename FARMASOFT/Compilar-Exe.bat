@echo off
echo Instalando modulo ps2exe (si no esta instalado)...
powershell -NoProfile -Command "if (-not (Get-Module -ListAvailable -Name ps2exe)) { Install-Module -Name ps2exe -Scope CurrentUser -Force }"

echo.
echo Generando FARMASOFT.exe...
powershell -NoProfile -Command "Invoke-ps2exe -inputFile '%~dp0GestorRutasDNS.ps1' -outputFile '%~dp0FARMASOFT.exe' -noConsole -title 'FARMASOFT' -requireAdmin"

echo.
echo Listo. Revisa la carpeta: FARMASOFT.exe
pause
