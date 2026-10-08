# Evaluar extracción con Ollama local

Prueba aislada de fase 5, con ocho textos ficticios y resultados esperados revisables. No lee S3, PostgreSQL, archivos médicos ni variables .env. No cambia Vitalia ni entrena el modelo. Requiere Node.js 22 o posterior y Ollama con qwen2.5:3b instalado.

## Ejecutar en Windows
Desde la raíz del repositorio:

```powershell
ollama list
node --test scripts/ia/evaluar-extraccion.test.mjs
node scripts/ia/evaluar-extraccion.mjs
```

Si el modelo no aparece en la lista:

```powershell
ollama pull qwen2.5:3b
```

Ollama debe estar abierto. El evaluador llama exclusivamente a http://127.0.0.1:11434/api/chat. El backend y el emulador no son necesarios. No ejecutar ollama serve si la aplicación ya está atendiendo ese puerto.

La evaluación ejecuta los ocho casos en orden y muestra OK o FALLO, duración y discrepancias. Puede tardar hasta dos minutos por caso antes de registrar un error de tiempo. Genera informes Markdown y JSON en la carpeta temporal del sistema, dentro de VitaliaHealth/ia-evaluaciones, y muestra las rutas completas. Los informes no se escriben en el repositorio.

## Qué se mide
- JSON y tipos válidos, claves exactas y fechas reales en DD-MM-AAAA.
- Fidelidad exacta de nombres, valores como texto, unidades y rangos, así como orden y cantidad de resultados.
- Ausencia de información inventada cuando faltan datos o el valor es ambiguo.
- Resistencia en un caso a una instrucción incrustada en el documento.

El modelo no devuelve datos_faltantes. El evaluador los deriva de campos null solo después de validar la estructura. No convierte una respuesta incorrecta en correcta: la fecha inválida produce fallo y cualquier discrepancia respecto del resultado esperado queda registrada.

Se usa esquema JSON, temperatura 0, semilla 42 y contexto 4096. Esto reduce variaciones, pero no garantiza precisión ni reproducibilidad idéntica en diferentes versiones o equipos. La primera duración puede incluir carga del modelo; son tiempos de petición completa, no un estudio de rendimiento.

## Interpretación
Un resultado 8/8 es una condición inicial para continuar evaluando, no aprobación clínica ni garantía de seguridad. Una ejecución con fallos termina con código 1 y aun así guarda el informe. Los seis tests automatizados verifican el evaluador con respuestas simuladas; no evalúan el modelo real.

Compartir la salida de consola y, si hay fallos, los apartados correspondientes del informe. Aún quedan por evaluar OCR, PDFs, imágenes, documentos más variados, explicación, revisión profesional y permisos. La licencia del modelo y su autorización como alternativa a OpenAI deben revisarse antes de su integración definitiva.

## Referencias
- https://docs.ollama.com/api/chat
- https://docs.ollama.com/capabilities/structured-outputs

## Segunda batería y prompt versión 3

Desde la raíz, ejecutar primero la original y luego la segunda:

```powershell
node --test scripts/ia/evaluar-extraccion.test.mjs scripts/ia/casos-independientes.test.mjs
node scripts/ia/evaluar-extraccion.mjs
node scripts/ia/evaluar-extraccion.mjs --independiente
```

La segunda batería contiene diez textos nuevos. Sus respuestas esperadas no se envían al modelo ni sus documentos se incorporan al prompt. Los informes nuevos identifican batería y versión del prompt.

La primera batería se utilizó para desarrollar el prompt (versión 1: 1/8; versión 2: 6/8, según el usuario). La segunda comprueba nuevos datos con el prompt fijado, pero cubre clases de errores conocidas y fue diseñada por el mismo autor: no es validación externa, clínica o estadística. Si se ajusta el prompt según sus fallos, deberá tratarse también como batería de desarrollo.
