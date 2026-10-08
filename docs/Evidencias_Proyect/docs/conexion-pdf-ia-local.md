# Conexión aislada PDF e IA local

createPdfExtraction une lector PDF y extractor Qwen3. Solo text_ready con texto no vacío llega al modelo. needs_ocr y rejected se detienen antes de la IA. Sin rutas HTTP, S3, PostgreSQL, Flutter, OCR ni revisión profesional persistente.

## Windows
Con Ollama abierto y qwen3:4b-instruct instalado, desde backend:

```powershell
npm test -- --runTestsByPath test/pdf-extraction.test.cjs test/pdf-reader.test.cjs test/ai-extraction.test.cjs
$LASTEXITCODE
node dist/ai/check-pdf.js
$LASTEXITCODE
```

Las pruebas deben mostrar 26 aprobadas. La comprobación real utiliza solo los tres PDFs ficticios incluidos. No necesita iniciar el servidor ni .env.

Resultados esperados:
- texto: requires_review, reading.text y ai con respuesta original, extracción e incidencias. approved siempre false.
- imagen: needs_ocr con ai null; no se envía al modelo.
- protegido: rejected con password_required y ai null; no se envía al modelo.

Si Ollama no responde: service_error, lectura conservada, ai null y código de salida 1. Si el modelo entrega JSON o estructura inválida: rejected con ai conservando la respuesta original. El comando termina con código 0 únicamente cuando los tres estados son los esperados. No equivale a precisión de la extracción ni aprobación profesional.

La conexión conserva tanto el texto leído como la respuesta original y las incidencias. No transforma fechas, cifras o unidades. Un resultado requires_review sin incidencias puede contener errores de fidelidad no detectados. Los límites y restricciones del lector y del módulo IA siguen vigentes; el PDF original debe contrastarse durante la revisión.

La entrada actual es sintética. No usar datos médicos reales. La conexión no evalúa explicaciones ni genera recomendaciones. Windows verificó el lector corregido con 18 pruebas y códigos 0; esta conexión nueva requiere su propia comprobación.
