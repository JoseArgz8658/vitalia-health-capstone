# CAM-008 — API autenticada de documentos
Autorización explícita para cuatro archivos: backend/package.json, package-lock.json,
src/app.ts y src/server.ts, 1 de octubre de 2026.

Motivo: montar rutas de carga/listado/descarga, conectar PostgreSQL y S3 y gestionar cierre.
Dependencias: multer 2.4.0 y @types/multer con versión exacta generada por npm.
Lógica, migración 004_document_audit, pruebas y guías en archivos nuevos.
No se modifica Flutter, la configuración privada ni el repositorio de metadatos existente.

Consecuencia: arranque exige S3 configurado y auditoría aplicada. Formatos PDF/JPEG/PNG, 10 MiB.
Documentos ajenos se tratan como inexistentes. Auditoría vinculada a la identidad de sesión.
No se expone clave interna S3 ni URL pública en la respuesta.

Validación: npm ci, TypeScript y 108 pruebas. Comprobación real preparada, pendiente en equipo del usuario.
La prueba real escribe un PDF sintético en S3 y lo borra al terminar; revierte PostgreSQL.
Ver límites de firmas y compensación de fallos en docs/api-documentos.md.

Reversión de código: volver a fase-4/almacenamiento-s3 y npm ci. Conservar la tabla nueva;
no borrar auditoría ni documentos para revertir el código. Detener servidor antes de cambiar de rama.
