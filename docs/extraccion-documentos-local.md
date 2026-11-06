# Conexión unificada de documentos e IA local

Módulo aislado createDocumentExtraction. Nuevos archivos, sin cambiar lector, OCR, extractor, rutas de servidor o dependencias.

## Windows
Con Ollama abierto y qwen3:4b-instruct instalado, desde backend:

```powershell
npm test -- --runTestsByPath test/document-extraction.test.cjs test/pdf-extraction.test.cjs test/ocr.test.cjs test/pdf-reader.test.cjs test/ai-extraction.test.cjs
$LASTEXITCODE
node dist/ai/check-documents.js
$LASTEXITCODE
```

Se esperan 47 pruebas aprobadas y código 0. El check utiliza cinco documentos ficticios incluidos, sin admitir rutas externas:

| Documento | Método esperado | Estado esperado |
| --- | --- | --- |
| PDF con texto | direct | requires_review |
| PDF escaneado | ocr | requires_review |
| PNG | ocr | requires_review |
| JPEG | ocr | requires_review |
| PDF protegido | null | rejected, sin ai |

El comando hace cuatro peticiones al modelo, una por documento legible, de forma secuencial. Puede tardar más que las pruebas simuladas. No requiere servidor, emulador, .env, PostgreSQL o S3. Compartir salida completa y códigos. Código 0 verifica los estados esperados, no precisión ni aprobación profesional. Si Ollama falla, muestra service_error y código 1; la lectura y texto disponibles se conservan.

## Selección y contrato
Para PDF, primero se ejecuta readPdfText. text_ready usa texto directo; needs_ocr invoca OCR para todas las páginas del documento. rejected detiene la cadena sin intentar OCR como alternativa. Para PNG/JPEG, se invoca OCR directamente. OCR rechazado también detiene la cadena. Solo texto no vacío, dentro de 12000 bytes, llega a Qwen3.

Se conservan reading, ocr, inputText y ai (incluye respuesta original, extracción e incidencias), source y method. approved siempre false. requires_review puede contener incidencias OCR y de IA; se revisan ambos objetos. Una estructura IA inválida produce rejected, conservando raw. Un fallo inesperado de lectura produce service_error sin exponer detalles internos.

Confianza OCR baja no bloquea por sí sola el envío: se conserva la incidencia y toda salida sigue requiriendo revisión. No se corrigen unidades, cifras o fechas. µ puede reconocerse como u; el modelo puede reproducir ese error. No considerar la explicación IA habilitada ni la extracción aprobada.

Los límites de los módulos anteriores siguen vigentes: PDF directo hasta diez páginas; OCR hasta tres, cuatro millones de píxeles por página, etc. Un PDF mixto que tiene algo de texto en cada página puede omitir contenido de imágenes y ser clasificado para lectura directa. La detección actual no asegura cobertura completa. Es necesario contrastar contra el documento original.

No hay conexión a S3, tablas de procesamiento, pantallas o revisión profesional persistente. No usar datos médicos reales. Esta entrega no crea cuentas de administrador o profesional.
