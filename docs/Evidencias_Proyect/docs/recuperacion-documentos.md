# Recuperación de cargas incompletas
Rama fase-4/recuperacion-documentos. Solo archivos nuevos.
El usuario confirmó Flutter analyze, pruebas y presentación del panel de documentos.

## Verificación desde backend
```powershell
npm ci
npm run check
npm test
node --env-file=.env dist/database/migrate-document-cleanup.js
node --env-file=.env dist/database/verify-document-recovery.js
node --env-file=.env dist/database/recover-documents.js
```

Resultados:
- Migración de recuperación de documentos aplicada.
- Recuperación de documentos correcta. Borrado S3 simulado y datos sintéticos revertidos.
- Cargas incompletas antiguas candidatas: N
- Solo consulta. No se modificó PostgreSQL ni S3.

La migración exige 004_document_audit. La prueba real de PostgreSQL crea tres documentos
sintéticos: pending antiguo, pending reciente y stored antiguo; comprueba que solo se
seleccione el incompleto antiguo. Simula el borrado S3 y revierte todos sus datos.
La selección de prueba se restringe a esos IDs; no procesa documentos de otras cuentas.
El comando de revisión normal no se conecta a AWS ni cambia datos.

## Aplicación manual
Para mantenimiento autorizado, después de revisar el resultado y detener cargas en curso:
```powershell
node --env-file=.env dist/database/recover-documents.js --apply
```
Este comando cambia a failed cargas incompletas mayores de una hora y solicita DeleteObject
para sus claves en S3. No borra documentos stored ni cuentas. Registra cada limpieza confirmada
en vitalia_document_cleanup, de modo que no se repita.
Lote de hasta 100. Bloqueo advisory por conexión impide dos recuperaciones concurrentes.
Revalida estado antes de borrar y verifica que la clave corresponda al paciente y documento.
Si falla S3 o el registro de limpieza, devuelve failed y permite reintentar.
En bucket versionado, DeleteObject puede dejar versiones históricas: no elimina esas versiones.
La antigüedad es una heurística; detener cargas antes de aplicar evita interferir con cargas anormalmente lentas.
La herramienta no se ejecuta automáticamente ni se programa en el servidor.
Quedan pendientes reconciliación automática y control distribuido de tiempos de carga.
No se requieren credenciales nuevas, cambios de .env ni cambios de Flutter.
