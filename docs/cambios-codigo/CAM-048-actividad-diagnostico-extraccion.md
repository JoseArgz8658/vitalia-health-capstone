# CAM-048: actividad visible y diagnóstico de extracción

Autorización: continuación de la fase de informe completo y petición explícita de indicar el procesamiento en curso (7 de octubre de 2026).

La consulta profesional muestra una barra indeterminada para trabajos en espera o en procesamiento. Actualizar extracción consulta el estado sin reenviar el documento. Si el trabajo falló, la revisión explica que no hay datos para aprobar y que actualizar no reintenta el procesamiento. No se muestra ausencia de incidencias como señal de éxito mientras el trabajo sigue activo.

El test de revisión ampliada quita el foco y el teclado antes de desplazar la confirmación. Pulsa únicamente un elemento alcanzable y comprueba que se envió la revisión antes de acceder al resultado. No se silencian advertencias de pulsaciones perdidas.

La extracción registra exclusivamente evento, categoría de fallo, versión del contrato y duración. No registra texto, nombres, respuestas ni mensajes de excepciones. Distingue HTTP, transporte, tiempo excedido, respuesta incompleta, formato JSON inválido y límite de respuesta. La consulta ofrece mensajes acotados para los fallos principales.

El prompt ampliado tiene revisión textual 2 y mantiene contrato 4. Se elimina la repetición del esquema y ejemplos del prompt anterior; el esquema completo continúa enviado a Ollama mediante format. Se conservan validaciones, límites, estados literales y campos independientes. Esto reduce texto de entrada, pero no demuestra por sí solo que resuelva el fallo observado. El timeout anterior de explicación no identifica la causa de esta extracción.

Validación local: compilación TypeScript y 33 pruebas en report-extraction, ai-extraction y document-extraction correctas. Flutter no está instalado en este entorno; ejecutar analyze y test en Windows. La salida backend enviada terminó en RUNS sin resumen: no permite afirmar que aquella ejecución completa pasó. Consultar LASTEXITCODE inmediatamente después de repetirla.

Reversión: volver al commit ec08b2bd3c700a831bd21153e38308da9da057d1. No cambia migraciones ni modifica originales o revisiones guardadas. Los trabajos fallidos no se reintentan automáticamente; para la comprobación usar una nueva carga ficticia.
