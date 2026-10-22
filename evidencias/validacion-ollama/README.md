# Validación de extracción con Ollama — Vitalia Health

## Objetivo
Detectar rangos de referencia generados por Ollama que no aparecen literalmente en el texto original de un examen médico.

## Problema
Un modelo de inteligencia artificial puede generar rangos de referencia que no están presentes en el documento. Estos valores requieren verificación humana y no deben aceptarse automáticamente.

## Solución implementada
- Se incorporó la incidencia `not_in_source` en `contract.ts`.
- Se normalizan espacios, mayúsculas y diferentes caracteres de guion antes de comparar.
- Se entrega el texto original del documento a `reviewExtraction`.
- Si un rango extraído no coincide con el texto original, se registra una incidencia.
- No se modifican automáticamente los resultados clínicos.
- Se mantiene `approved: false` y la revisión humana obligatoria.

## Validaciones realizadas
- 427 pruebas automatizadas aprobadas, distribuidas en 40 suites.
- Compilación TypeScript completada correctamente.
- Imagen Docker reconstruida y servicios operativos.
- Validación `not_in_source` presente en el worker.
- Extracción real de un PDF ficticio con `qwen3:4b-instruct`.
- Los tres rangos ausentes del PDF se conservaron como `null`.
- Se registraron tres incidencias `not_extracted`.
- El documento permaneció en estado `requires_review`.

## Evidencias
- E06-pruebas-backend.txt: resultados de las pruebas automatizadas.
- E07-estado-docker.txt: estado de los servicios.
- E08-validacion-worker.txt: comprobación de la validación en Docker.
- E09-prueba-pdf-ollama.txt: extracción del documento ficticio.

## Limitaciones
La validación utiliza coincidencias textuales normalizadas. Puede generar advertencias ante diferencias de formato u OCR y no garantiza detectar todas las alucinaciones del modelo.

La presencia literal de un rango tampoco demuestra que corresponda clínicamente al examen correcto.

La revisión por un profesional autorizado continúa siendo obligatoria.
