# FARMASOFT - Gestor de Rutas y DNS

App con interfaz grafica (WinForms/PowerShell) que reemplaza al script `.bat` original de gestion de rutas y añade la gestion de DNS. No muestra ventana de consola, solo la interfaz grafica.

## Uso

1. Doble clic en `Iniciar.bat` (o ejecutar `GestorRutasDNS.ps1` con PowerShell).
2. La app solicita permisos de administrador automaticamente.

## Rutas

- Introduce la Gateway y pulsa **Añadir rutas** para crear las rutas estaticas persistentes:
  - 172.16.0.0/24
  - 172.16.2.0/24
  - 172.16.4.0/24
- Pulsa **Eliminar rutas** para quitarlas.
- El resultado de cada operacion se muestra en el panel inferior.

## DNS

- Selecciona el adaptador de red (solo se listan los que estan activos).
- Pulsa **Añadir DNS** para aplicar, en este orden, los servidores predefinidos:
  1. 172.16.4.100
  2. 172.16.2.100
  3. 172.16.0.100
- Pulsa **Restaurar DNS** para volver a obtener el DNS automaticamente por DHCP.

## Requisitos

- Windows con PowerShell 5.0 o superior.
- Permisos de administrador (se solicitan automaticamente).
