# FARMASOFT - Gestor de DNS y Routes

App con interfaz grafica (WinForms/PowerShell) para gestionar rutas estaticas y DNS. No muestra ventana de consola, solo la interfaz grafica.

## Uso

1. Doble clic en `Iniciar.bat` (lanza `GestorRutasDNS.ps1` sin mostrar consola).
2. La app solicita permisos de administrador automaticamente.

## Rutas

- **Gateway**: se autodetecta al abrir la app (a partir de la IP local que empieza por 172.x, cambiando el ultimo octeto por 1) y se puede volver a detectar con el boton **Detectar**, o escribirla a mano.
- **Añadir**: crea las rutas estaticas persistentes:
  - 172.16.0.0/24
  - 172.16.2.0/24
  - 172.16.4.0/24
- **Eliminar**: las elimina.
- **Comprobar**: indica si cada una ya existe o no, sin modificar nada.

## DNS

- Selecciona el adaptador de red (solo se listan los que estan activos).
- **Añadir DNS**: aplica, en este orden, los servidores predefinidos:
  1. 172.16.4.100
  2. 172.16.2.100
  3. 172.16.0.100
  4. 8.8.8.8
- **Restaurar DNS**: aplica 8.8.8.8 y 1.1.1.1.

## Registro de actividad

Tabla con Hora / Evento / Estado, coloreada segun resultado: verde (agregado/aplicado/restaurado/existe), ambar (eliminado), rojo (error), gris (ya existia/no existe).

## Requisitos

- Windows con PowerShell 5.0 o superior.
- Permisos de administrador (se solicitan automaticamente).
