# Procesador manual de documentos privados

Ejecuta un documento por comando desde el backend. Requiere la migración 006 ya aplicada, PostgreSQL, configuración privada S3 en `.env` y Ollama local con `qwen3:4b-instruct`. No requiere otra migración ni dependencias nuevas.

## Comprobación en Windows

Usa exclusivamente un documento ficticio que hayas cargado mediante la aplicación. En pgAdmin, abre Query Tool sobre `vitalia_dev` y consulta:

```sql
SELECT id, original_name, content_type, created_at
FROM public.vitalia_documents
WHERE status = 'stored'
ORDER BY created_at DESC;
```

Identifica el archivo ficticio y copia su `id`. No compartas listados de documentos reales. En PowerShell, desde `backend`, sustituye el UUID en la primera línea:

```powershell
$documento = 'UUID_DEL_DOCUMENTO_FICTICIO'
npm test -- --runTestsByPath test/processing-worker.test.cjs test/document-processing.test.cjs test/document-extraction.test.cjs
node --env-file=.env dist/database/process-document.js --document $documento
$LASTEXITCODE
```

La consulta muestra ID, tipo, tamaño y estado. No reserva trabajos, descarga S3 ni llama a IA. Para un documento nuevo debe aparecer `sin_trabajo`. Si aparece `queued`, puede continuar; cualquier otro estado impide repetirlo.

Mantén Ollama abierto y ejecuta:

```powershell
node --env-file=.env dist/database/process-document.js --document $documento --apply
$LASTEXITCODE
```

`--apply` comprueba el bucket privado y la disponibilidad del modelo antes de reservar un trabajo. Reclama el trabajo de forma atómica, descarga el objeto esperado, valida tamaño y firma, ejecuta lectura directa u OCR e IA y persiste el resultado completo en PostgreSQL. No imprime texto, resultados médicos ni claves S3. Conserva el archivo original.

Resultado habitual: `outcome: requires_review`, `approved: false` y código 0. Un documento rechazado también devuelve código 0: es un resultado controlado, no una extracción aprobada. Fallos de servicio o procesamiento devuelven código 1. Repite la consulta sin `--apply` para comprobar el estado final.

## Alcance y límites

Este comando es una herramienta del operador local con credenciales del backend. No representa una sesión de paciente ni autorización profesional y no expone una ruta HTTP. Todavía no hay pantalla de revisión, aprobación, cola automática ni auditoría profesional.

Un documento admite un solo trabajo con la migración actual. No se sobrescriben resultados ni se reintentan trabajos terminales. Si se interrumpe el proceso, puede quedar en `processing`; no cambies ese estado manualmente. La recuperación de trabajos interrumpidos queda pendiente.

Los fallos posteriores a reclamar se registran como `processing_failed` cuando PostgreSQL responde. Si falla también ese registro, la salida indica `failureRecorded: false`; no afirma que el estado se haya actualizado.

Los tiempos incluyen descarga, lectura/OCR e IA; no hay garantía de tres segundos. El OCR puede transformar símbolos como μ en u aun con confianza alta. Toda extracción exige comparación con el original; no constituye diagnóstico ni aprobación.

El comando guarda datos de manera persistente y no los revierte. La comprobación completa con S3, PostgreSQL y Ollama debe ejecutarse en el entorno local; las pruebas automatizadas del procesador usan sustitutos de esos servicios.
