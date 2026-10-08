# CAM-025 — Procesador manual

Autorización: el usuario autorizó crear el procesador manual de un documento privado por ejecución, pruebas y documentación.

Se agregan `backend/src/processing/worker.ts`, `manual.ts`, `backend/src/database/process-document.ts`, `backend/test/processing-worker.test.cjs` y documentación. No se modifica código existente, esquema ni dependencias.

El comando ofrece consulta previa y ejecución explícita. La reserva y reclamación protegen contra repetición concurrente; valida clave del paciente, tamaño, tipo y firma antes de IA. Conserva el original S3 y resultados pendientes de revisión. El operador local tiene acceso técnico con credenciales de backend; no se agrega un endpoint público.

Validación: compilación TypeScript y 37 pruebas en `processing-worker`, `document-processing` y `document-extraction` aprobadas. Cubren reclamación, objetos incorrectos, fallos de descarga, persistencia, estados terminales y argumentos. Comprobación integral en el equipo del usuario pendiente.

Reversión: retirar los archivos nuevos y dejar de ejecutar el comando. Los registros ya creados y los documentos S3 no se eliminan; retirar el código no revierte datos. Recuperación de trabajos interrumpidos y reprocesamiento quedan fuera de este cambio.
