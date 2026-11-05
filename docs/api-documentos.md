# API de documentos — integración de PostgreSQL y S3

Rama fase-4/api-documentos. Flutter sigue sin cambios.
Sesión válida y rol paciente requeridos. Identidad extraída de la sesión, no del formulario.
No se habilita todavía acceso del profesional a documentos de pacientes.

## Actualizar y verificar
Detén el backend con Ctrl+C antes de cambiar de rama. Desde la raíz, guarda cambios locales:
```powershell
git fetch origin
git switch fase-4/api-documentos
cd backend
npm ci
npm run check
npm test
```

Con PostgreSQL activo y el perfil AWS ya configurado, desde backend:
```powershell
node --env-file=.env dist/database/check.js
node --env-file=.env dist/storage/check.js
node --env-file=.env dist/database/migrate-document-audit.js
node --env-file=.env dist/database/verify-document-api.js
```

Ejecuta uno por uno y detente ante un error. La migración requiere 003_documents ya aplicada.
Resultado de migración:
Migración de auditoría de documentos aplicada.

Resultado de comprobación:
API de documentos correcta: carga, listado, descarga y aislamiento. Datos sintéticos revertidos y objeto S3 eliminado.

El comando verify-document-api usa PostgreSQL y AWS reales: crea un PDF sintético pequeño,
lo sube a una clave aleatoria propia, prueba dos identidades y descarga el contenido.
No requiere documentos médicos ni cuenta de paciente real. No imprime contraseñas ni tokens.
Revierte cuentas, sesiones, documentos y auditoría en PostgreSQL y solicita DeleteObject para la clave creada.
Si la limpieza falla, devuelve error y muestra la clave sintética para revisión.
En buckets con versionado, DeleteObject sin VersionId puede dejar versiones históricas; utiliza un bucket
de desarrollo sin versionado para esta prueba, o coordina la limpieza de versiones con el administrador.
El script no elimina otros objetos del bucket.

Después:
```powershell
npm start
```

El servidor ahora verifica S3 y las tablas de documentos/auditoría al arrancar.
No cambies .env: reutiliza PostgreSQL, AWS_REGION, S3_BUCKET y AWS_PROFILE existentes.

## Contrato
- POST /api/documents — multipart/form-data. Archivo en file; campos examName, examType, examDate.
  Respuesta 201 con document. PDF, JPEG o PNG; máximo 10 MiB.
- GET /api/documents?limit=20&offset=0 — solo documentos stored del paciente. Respuesta documents.
- GET /api/documents/:id/file — descarga adjunta autenticada, sin URL pública.
Todas usan Authorization: Bearer TOKEN. No pegar tokens en mensajes.
Documento ajeno o inexistente: misma respuesta 404.
Auditoría registra carga confirmada, listado y autorización de descarga, sin contenido del examen.
Una descarga auditada no acredita que el navegador haya recibido todos los bytes.

## Consistencia y límites
Reserva pending, almacenamiento S3, confirmación stored + auditoría en transacción PostgreSQL.
Ante fallo intenta marcar failed y eliminar el objeto. Pending/failed no aparecen en historial.
S3 y PostgreSQL no comparten una transacción: un cierre abrupto o una limpieza fallida
pueden dejar reservas pendientes u objetos huérfanos. Falta reconciliación automática.
Carga y descarga concurrentes limitadas a dos por proceso; no es un control distribuido.
Validación de firmas básicas y coherencia MIME/extensión; no es parser completo ni antivirus.
La integración de Flutter, recuperación automática y revisión profesional quedan pendientes.
