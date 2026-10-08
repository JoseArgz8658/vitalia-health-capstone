# Módulo aislado de extracción local

Primer módulo de fase 5 para texto ficticio. Qwen3 sigue siendo candidato supervisado: obtuvo 7/8 y 7/10 en las baterías, con fechas imposibles y una unidad omitida. La reevaluación con comparación completa confirmó esas discrepancias. No se conecta a S3, PostgreSQL ni Flutter; no añade endpoints, OCR, revisión profesional persistente o explicaciones.

## Ejecutar en Windows
Con Ollama abierto y qwen3:4b-instruct descargado, desde la raíz:

```powershell
cd backend
npm run build
npm test -- --runTestsByPath test/ai-extraction.test.cjs
node dist/ai/check.js
```

No requiere iniciar servidor, emulador ni cargar .env. El último comando envía un texto ficticio fijo que incluye fecha imposible y valor ilegible. Muestra texto, respuesta original, extracción e incidencias. No guarda ni modifica datos. El resultado exacto puede variar: debe mostrar approved: false y requires_review o rejected. Si el modelo devuelve fecha imposible, debe existir invalid_date. Si devuelve null, debe existir not_extracted. Compartir la salida completa.

## Contrato
createLocalExtractor devuelve una función que recibe texto y llama únicamente a http://127.0.0.1:11434/api/chat, sin seguir redirecciones. Modelo predeterminado qwen3:4b-instruct. Prompt congelado versión 3, temperatura 0, semilla 42, contexto 4096 y máximo 1600 tokens de respuesta. La copia del prompt en backend es independiente del evaluador: futuros cambios deben versionarse y compararse explícitamente.

Salida: raw (contenido original del modelo), extraction (estructura validada o null), incidents, status, approved siempre false, model, promptVersion y elapsedMs.

- rejected: JSON o estructura inválida; no se acepta extracción.
- requires_review: estructura correcta, con o sin incidencias. No implica fidelidad al documento.
- invalid_date: fecha de calendario inválida o formato distinto de DD-MM-AAAA. Se conserva el dato original; no se corrige automáticamente.
- not_extracted: campo null; puede estar presente en el documento. No significa ausencia confirmada.
- no_results: lista vacía; debe comprobarse contra el original.

El módulo no puede detectar todas las cifras inventadas, unidades omitidas representadas como otro texto o instrucciones incrustadas exitosas. Sin referencia esperada no realiza comparación de fidelidad. El contraste profesional sigue siendo necesario y todavía no está implementado.

Límites: 12000 bytes de texto, 100 resultados, 500 caracteres por campo, 128 KiB de respuesta HTTP y 120 segundos para petición y lectura. El límite de entrada evita textos largos, pero no garantiza que cualquier combinación alcance el contexto disponible. Las respuestas incompletas se rechazan. No se acredita concurrencia, uso clínico ni producción. La conexión local no certifica por sí sola la procedencia del modelo instalado: utilizar solo el modelo local indicado.

No usar datos reales durante estas pruebas. La licencia y autorización definitiva del modelo siguen pendientes antes de integración.
