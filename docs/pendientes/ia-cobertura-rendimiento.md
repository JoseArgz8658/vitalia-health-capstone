# Pendientes de IA — retomar después de la fase visual

Estado: abierto. Base comprobada por el usuario: fase-5/informe-completo, commit 4e946fed.
La fase 6 mejora la interfaz; no cierra los siguientes pendientes.

## Comprobado
- Extracción del PDF sintético completo y aprobación profesional.
- Consulta de datos revisados y algunas preguntas educativas.
- Definiciones de los dieciséis indicadores del examen mediante catálogo con fuentes.
- 121 pruebas automatizadas focalizadas. No equivalen a certificación clínica.

## Por resolver
1. Cobertura: indicadores y nombres fuera del catálogo; no inventar significado.
2. Rendimiento: medir carga inicial, generación, tamaño del contexto y bloques con Ollama en RTX 3050. Dos intentos anteriores alcanzaron 120 segundos. Los bloques acotados entregaron cobertura insuficiente; el catálogo permitió explicar el examen habitual. La velocidad de generación no se considera resuelta.
3. Preguntas naturales y seguimientos: ampliar batería independiente y revisar pertinencia de las respuestas, no solo estructura.
4. PNG/JPG: probar flujo completo desde aplicación con documentos sintéticos; distinguir estos ensayos manuales de las pruebas automatizadas de OCR existentes.
5. Explicaciones cortas y conceptos desconocidos: todavía pueden depender de Ollama y fallar.
6. Fuentes y exactitud: revisar nuevas definiciones antes de ampliar catálogo; no incorporar automáticamente respuestas del chat.
7. Usabilidad de espera y errores: resolver en fase visual y probar que no se pierde conversación.
8. Ejemplos opcionales: ofrecer ejemplo sencillo cuando corresponda, respetar aceptación o rechazo del paciente.

## Evidencia que debemos recoger
Fecha, versión/commit, modelo, pregunta sintética, resultado esperado y observado, tiempo, categoría del fallo, ajuste y nueva comprobación. Nunca adjuntar secretos ni datos clínicos reales.

## Criterio de retoma y cierre
Retomar tras comprobar navegación paciente/profesional y chat en web y Android. Revisar este archivo antes de planificar nuevas funciones IA. Ejecutar pruebas automatizadas y batería independiente real con Ollama; comprobar semántica y tiempos. Documentar limitaciones restantes. Ajustar prompt/contexto no es entrenar el modelo.
