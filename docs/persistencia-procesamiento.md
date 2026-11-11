# Persistencia aislada de procesamiento — fase 5

Migración 006 añade public.vitalia_document_processing. No modifica cuentas o documentos existentes, ni migra resultados desde los informes temporales. No conecta S3, Ollama, rutas HTTP o pantallas: almacena resultados proporcionados por el servicio interno futuro.

## Obtener código y comprobar
Desde backend, en la rama fase-5/persistencia-procesamiento:

```powershell
npm test -- --runTestsByPath test/document-processing.test.cjs test/additional-migration.test.cjs
$LASTEXITCODE
```

Se esperan 17 pruebas aprobadas y código 0. No hay dependencias nuevas.

## Aplicar a PostgreSQL local
Usar el mismo backend/.env privado y la base de desarrollo ya configurada. No recrear la base ni cambiar contraseñas. La migración 005_document_cleanup debe estar aplicada.

Desde backend:

```powershell
node --env-file=.env dist/database/check.js
$LASTEXITCODE
```

Solo si confirma conexión y código 0:

```powershell
node --env-file=.env dist/database/migrate-document-processing.js
$LASTEXITCODE
```

Esperado: Migración de procesamiento aplicada. Código 0. La migración se aplica en transacción, con bloqueo y huella normalizada LF/CRLF, usando el mecanismo existente. Repetir el comando debe mostrar La migración de procesamiento ya estaba aplicada. No reescribir SQL después de aplicar: cambios futuros requieren otra migración.

## Verificar persistencia real sin dejar datos de prueba

```powershell
node --env-file=.env dist/database/verify-document-processing.js
$LASTEXITCODE
```

Esperado: Persistencia y aislamiento de procesamiento correctos. Datos sintéticos revertidos. Código 0.

La comprobación crea dos cuentas y metadatos ficticios dentro de una transacción; verifica propiedad, bloqueo de duplicados, reclamo único, preservación del resultado y prohibición de sobrescribir el resultado terminado. Revierte y comprueba que no persista el procesamiento. No imprime contraseñas ni hashes, no consulta S3/Ollama ni sube PDFs. El estado stored del documento es exclusivamente metadato sintético de prueba, no evidencia de un objeto S3.

Si falla, detenerse y compartir mensaje y código; no borrar tablas ni editar registros de migración para forzarlo. No compartir .env.

## Qué se almacena
| Campo | Función |
| --- | --- |
| id, document_id | UUID del procesamiento y documento asociado |
| status | queued, processing, requires_review, rejected o failed |
| model, prompt_version | Modelo y versión previstos para el trabajo |
| result | JSON original de la conexión: lectura, OCR, texto, respuesta IA, extracción e incidencias |
| failure_code | Código controlado de interrupción o fallo técnico sin resultado |
| created_at, started_at, finished_at | Trazabilidad de tiempos |

No se crea un estado aprobado. La tabla exige approved false en todo resultado; la revisión profesional será un flujo posterior y deberá conservar este original.

## Operaciones y permisos
queueDocumentProcessing recibe identidad autenticada de paciente y admite solo documentos stored propios. No aceptar una identidad elegida desde el cuerpo de una futura petición HTTP. Duplicado o documento no permitido devuelve null sin revelar detalles. Solo un registro por documento en esta versión: no hay reintentos ni historial de nuevas versiones todavía.

claimDocumentProcessing cambia queued→processing atómicamente y devuelve metadatos del trabajo. completeDocumentProcessing solo finaliza processing, valida estructura, fuente MIME y modelo/versión cuando hay IA; un segundo cierre devuelve false sin sobrescribir. service_error se almacena como failed conservando el resultado recibido. failDocumentProcessing permite cerrar processing sin resultado con un código controlado.

findPatientProcessingStatus solo entrega identificador, estado y tiempos del documento propio. No devuelve texto ni extracción sin revisión. findProcessingForWorker es una consulta técnica interna sin autorización clínica: nunca exponerla como endpoint de paciente o profesional. Los permisos profesionales y asignaciones siguen pendientes.

La cola aún no se ejecuta automáticamente. Un trabajo detenido en processing no se recupera solo; failDocumentProcessing existe para el servicio interno futuro, no como comando masivo. No mantener una transacción de base abierta mientras el modelo procesa. No se guardan bytes de PDF/imágenes en la tabla.

Los resultados pueden contener datos sensibles cuando se integre el sistema: por ahora solo datos ficticios. No hay cifrado adicional del contenido, políticas de retención o aprobación clínica implementadas en este paso.

## Reversión
Restaurar el código previo deja esta tabla nueva sin uso y conserva los datos. No eliminar tabla, resultados o registro de migración sin una reversión específica autorizada. La migración no necesita ejecutarse para usar las funciones anteriores de carga y lectura aislada.
