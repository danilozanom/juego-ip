# FARMASOFT - Gestor de Rutas y DNS

App con interfaz grafica (WinForms/PowerShell) que reemplaza al script `.bat` original de gestion de rutas y añade gestion de DNS.

## Uso

1. Doble clic en `Iniciar.bat` (o ejecutar `GestorRutasDNS.ps1` con PowerShell).
2. La app solicita permisos de administrador automaticamente.

## Pestaña "Rutas"

- Introduce la Gateway y pulsa **Agregar rutas** para crear las rutas estaticas persistentes:
  - 172.16.0.0/24
  - 172.16.2.0/24
  - 172.16.4.0/24
- Pulsa **Eliminar rutas** para quitarlas.
- El resultado de cada operacion se muestra en el panel inferior (AGREGADA, ELIMINADA, YA EXISTIA, NO EXISTIA, ERROR).

## Pestaña "DNS"

- Selecciona el adaptador de red (solo se listan los que estan activos).
- Introduce DNS Preferido y/o Alternativo y pulsa **Aplicar DNS**.
- Pulsa **Restaurar DNS (DHCP)** para volver a obtener el DNS automaticamente por DHCP.

## Requisitos

- Windows con PowerShell 5.0 o superior.
- Permisos de administrador (se solicitan automaticamente).
