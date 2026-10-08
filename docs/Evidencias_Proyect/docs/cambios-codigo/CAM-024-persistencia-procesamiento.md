# CAM-024 — Persistencia aislada de procesamiento

## Autorización
El usuario autorizó migración, módulo y todo lo correspondiente el 1 de octubre de 2026.

## Archivos nuevos
Migración 006_document_processing.sql; backend/src/processing/result.ts y repository.ts; comandos database/migrate-document-processing.ts y verify-document-processing.ts; prueba document-processing.test.cjs; guía y avance. Sin cambios a código existente o dependencias.

Tabla con documento único, estados, modelo, prompt, resultado JSON y tiempos. Reclamo/finalización condicionados por estado impiden dobles reclamos/sobrescritura. Registro paciente restringido a documento guardado propio. Consulta paciente no devuelve resultados sin revisión. Original sin correcciones y approved false.

## Verificación
Compilación y 17 pruebas aprobadas en dos suites: trece nuevas y cuatro del mecanismo existente de migración. PostgreSQL real no está disponible aquí. Comprobación Windows crea solo metadatos/cuentas ficticios en transacción y revierte, sin S3/Ollama; aplicación y prueba quedan pendientes.

## Límites y reversión
Un registro por documento; aún sin reintentos, recuperación automática, ejecución de cola, permisos profesionales o endpoints. Mantener original para revisión posterior.

Restaurar código previo y conservar tabla sin uso. Eliminar archivos nuevos no revierte una migración aplicada; no borrar tabla ni registro de migración sin plan autorizado que preserve datos.
