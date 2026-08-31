# FARMASOFT - Gestor de DNS y Routes

Script `.bat` de consola (sin ventana grafica, sin `.exe`) para gestionar las rutas estaticas y el DNS del equipo, con menu numerado y colores.

## Uso

1. Doble clic en `FARMASOFT.bat`.
2. Pide permisos de administrador automaticamente.
3. Elige una opcion del menu (1-6).

## Rutas

- **[1] Anadir rutas**: detecta la Gateway automaticamente (a partir de la IP local que empieza por 172.x, cambiando el ultimo octeto por 1) y permite corregirla antes de aplicarla. Crea las rutas estaticas persistentes:
  - 172.16.0.0/24
  - 172.16.2.0/24
  - 172.16.4.0/24
- **[2] Eliminar rutas**: las elimina.
- **[3] Comprobar rutas**: indica si cada una ya existe o no, sin modificar nada.

## DNS

- **[4] Anadir DNS**: detecta el adaptador conectado (si hay varios, deja elegir) y aplica, en este orden:
  1. 172.16.4.100
  2. 172.16.2.100
  3. 172.16.0.100
  4. 8.8.8.8
- **[5] Restaurar DNS**: aplica 8.8.8.8 y 1.1.1.1.

## Requisitos

- Windows (usa `route`, `netsh` e `ipconfig`, comandos nativos de cmd).
- Permisos de administrador (se solicitan automaticamente al abrir el `.bat`).
