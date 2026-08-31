@echo off
setlocal EnableDelayedExpansion
title FARMASOFT - Gestor de DNS y Routes
color 1F
mode con: cols=76 lines=34

:: ==========================================================
:: Comprobar permisos de Administrador
:: ==========================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: ==========================================================
:: Configuracion
:: ==========================================================
set "R1=172.16.0.0"
set "R2=172.16.2.0"
set "R3=172.16.4.0"
set "MASCARA=255.255.255.0"

set "DNS1=172.16.4.100"
set "DNS2=172.16.2.100"
set "DNS3=172.16.0.100"
set "DNS4=8.8.8.8"

set "DNSR1=8.8.8.8"
set "DNSR2=1.1.1.1"

set "LINEA=========================================================================="

set "GW="
set "ADAPTADOR="

goto MENU

:: ==========================================================
:: Cabecera
:: ==========================================================
:CABECERA
echo %LINEA%
echo.
echo                              F A R M A S O F T
echo                           Gestor de DNS y Routes
echo.
echo %LINEA%
goto :eof

:: ==========================================================
:: MENU
:: ==========================================================
:MENU
cls
call :CABECERA
echo.
echo    [1]  Anadir rutas
echo    [2]  Eliminar rutas
echo    [3]  Comprobar rutas
echo    [4]  Anadir DNS
echo    [5]  Restaurar DNS
echo    [6]  Salir
echo.
echo %LINEA%
echo.
set /p OPCION=   Selecciona una opcion:

if "%OPCION%"=="1" goto AGREGAR_RUTAS
if "%OPCION%"=="2" goto ELIMINAR_RUTAS
if "%OPCION%"=="3" goto COMPROBAR_RUTAS
if "%OPCION%"=="4" goto AGREGAR_DNS
if "%OPCION%"=="5" goto RESTAURAR_DNS
if "%OPCION%"=="6" exit
goto MENU

:: ==========================================================
:: RUTAS - Anadir
:: ==========================================================
:AGREGAR_RUTAS
cls
call :CABECERA
echo.
echo    RUTAS
echo.
call :DETECTAR_GATEWAY
if defined GW (
    echo    Gateway detectada: !GW!
) else (
    echo    No se pudo detectar la Gateway automaticamente.
)
echo.
set /p GW_NUEVA=   Pulsa Enter para usarla, o escribe otra Gateway:
if not "!GW_NUEVA!"=="" set "GW=!GW_NUEVA!"

if not defined GW (
    echo.
    echo    Debes indicar una Gateway valida.
    echo.
    echo %LINEA%
    pause
    goto MENU
)

echo.
echo    Procesando...
echo.
call :AGREGAR_RUTA %R1%
call :AGREGAR_RUTA %R2%
call :AGREGAR_RUTA %R3%
echo.
echo %LINEA%
pause
goto MENU

:: ==========================================================
:: RUTAS - Eliminar
:: ==========================================================
:ELIMINAR_RUTAS
cls
call :CABECERA
echo.
echo    RUTAS
echo.
echo    Procesando...
echo.
call :ELIMINAR_RUTA %R1%
call :ELIMINAR_RUTA %R2%
call :ELIMINAR_RUTA %R3%
echo.
echo %LINEA%
pause
goto MENU

:: ==========================================================
:: RUTAS - Comprobar
:: ==========================================================
:COMPROBAR_RUTAS
cls
call :CABECERA
echo.
echo    RUTAS
echo.
call :COMPROBAR_RUTA %R1%
call :COMPROBAR_RUTA %R2%
call :COMPROBAR_RUTA %R3%
echo.
echo %LINEA%
pause
goto MENU

:: ==========================================================
:: DNS - Anadir
:: ==========================================================
:AGREGAR_DNS
cls
call :CABECERA
echo.
echo    DNS
echo.
call :SELECCIONAR_ADAPTADOR
if not defined ADAPTADOR (
    echo %LINEA%
    pause
    goto MENU
)
echo.
echo    Se aplicaran: %DNS1% -^> %DNS2% -^> %DNS3% -^> %DNS4%
echo.
echo    Procesando...
netsh interface ip set dns name="!ADAPTADOR!" source=static addr=%DNS1% >nul
netsh interface ip add dns name="!ADAPTADOR!" addr=%DNS2% index=2 >nul
netsh interface ip add dns name="!ADAPTADOR!" addr=%DNS3% index=3 >nul
netsh interface ip add dns name="!ADAPTADOR!" addr=%DNS4% index=4 >nul
echo    [OK]      DNS aplicado en "!ADAPTADOR!"
echo.
echo %LINEA%
pause
goto MENU

:: ==========================================================
:: DNS - Restaurar
:: ==========================================================
:RESTAURAR_DNS
cls
call :CABECERA
echo.
echo    DNS
echo.
call :SELECCIONAR_ADAPTADOR
if not defined ADAPTADOR (
    echo %LINEA%
    pause
    goto MENU
)
echo.
echo    Se aplicaran: %DNSR1% -^> %DNSR2%
echo.
echo    Procesando...
netsh interface ip set dns name="!ADAPTADOR!" source=static addr=%DNSR1% >nul
netsh interface ip add dns name="!ADAPTADOR!" addr=%DNSR2% index=2 >nul
echo    [OK]      DNS restaurado en "!ADAPTADOR!"
echo.
echo %LINEA%
pause
goto MENU

:: ==========================================================
:: Funcion: agregar una ruta
:: ==========================================================
:AGREGAR_RUTA
route print | find "%1" >nul
if errorlevel 1 (
    route -p add %1 mask %MASCARA% !GW! >nul
    if errorlevel 1 (
        echo    [ERROR]   %1
    ) else (
        echo    [OK]      %1   agregada
    )
) else (
    echo    [EXISTE]  %1   ya existia
)
exit /b

:: ==========================================================
:: Funcion: eliminar una ruta
:: ==========================================================
:ELIMINAR_RUTA
route print | find "%1" >nul
if errorlevel 1 (
    echo    [--]      %1   no existia
) else (
    route delete %1 >nul
    if errorlevel 1 (
        echo    [ERROR]   %1
    ) else (
        echo    [OK]      %1   eliminada
    )
)
exit /b

:: ==========================================================
:: Funcion: comprobar una ruta
:: ==========================================================
:COMPROBAR_RUTA
route print | find "%1" >nul
if errorlevel 1 (
    echo    [NO]      %1   no existe
) else (
    echo    [SI]      %1   existe
)
exit /b

:: ==========================================================
:: Funcion: detectar Gateway a partir de la IP 172.x del equipo
:: (mismo criterio usado en la version grafica: se toma la IP
:: local que empieza por 172. y se cambia el ultimo octeto por 1)
:: ==========================================================
:DETECTAR_GATEWAY
set "GW="
set "IP172="
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /r "IPv4.*172\."') do (
    if not defined IP172 set "IP172=%%a"
)
set "IP172=!IP172: =!"
if defined IP172 (
    for /f "tokens=1,2,3 delims=." %%a in ("!IP172!") do set "GW=%%a.%%b.%%c.1"
) else (
    for /f "tokens=3" %%a in ('route print ^| findstr /r "^ *0.0.0.0 *0.0.0.0"') do set "GW=%%a"
)
exit /b

:: ==========================================================
:: Funcion: listar adaptadores conectados y elegir uno
:: ==========================================================
:SELECCIONAR_ADAPTADOR
set "ADAPTADOR="
set "CONTADOR=0"
for /f "skip=2 tokens=1,2,3,4,*" %%a in ('netsh interface ipv4 show interfaces') do (
    if /i "%%d"=="connected" (
        set /a CONTADOR+=1
        set "IF!CONTADOR!=%%e"
    )
)

if "!CONTADOR!"=="0" (
    echo    No se encontro ningun adaptador conectado.
    exit /b
)

if "!CONTADOR!"=="1" (
    set "ADAPTADOR=!IF1!"
    echo    Adaptador detectado: !ADAPTADOR!
    exit /b
)

echo    Adaptadores disponibles:
echo.
for /l %%i in (1,1,!CONTADOR!) do echo       [%%i] !IF%%i!
echo.
set /p SEL=   Elige un adaptador:
set "ADAPTADOR=!IF%SEL%!"
exit /b
