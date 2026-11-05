# CAM-077 — Manual Windows y datos de pruebas del equipo

## Motivo

Actualizar la instalación para computadores Windows e incorporar la recuperación de Docker confirmada por José y el bucket AWS compartido con el equipo.

## Cambios

README reestructurado para ejecución con y sin Docker. Se documentan componentes WSL/virtualización, reinicio, comprobación de Compose, configuración por entorno, acceso individual al bucket existente y caducidad de credenciales temporales. Se añaden procedimientos de respaldo y restauración PostgreSQL en una base vacía, y se distingue una copia local de una base central.

Se advierte que PostgreSQL conserva referencias pero no copia objetos S3, y que eliminar documentos desde bases clonadas con el mismo bucket puede afectar a otros integrantes. Los respaldos contienen datos de cuentas y sesiones y requieren revisión antes de compartirlos de forma privada.

## Evidencia y límites

El usuario confirmó que Docker arrancó después de habilitar componentes Windows y reiniciar. Salida comunicada: Docker 29.8.0, tipo linux, WSL 2, Flutter 3.44.6 y Node 24.15.0. Compose no imprimió versión y queda pendiente de comprobación. El archivo .env raíz no existe y backend/.env sí existe.

Se cotejaron README, Compose y script de configuración. Compose fija PGHOST=postgres, por lo que una conexión a servidor remoto no se consigue cambiando solo .env. No se modifican scripts, configuración de runtime, migraciones ni permisos. No se exportó ni compartió ninguna base real. Arranque completo de Compose y restauración quedan pendientes de ejecución en Windows.

## Reversión

Revertir los commits de documentación. No hay cambios en datos ni servicios.
