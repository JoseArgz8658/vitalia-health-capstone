# CAM-037 — Formato de generación por modo

Corrección dentro del ajuste de prompt y pruebas autorizado. Tras la evaluación 9/11, se restringe definitions a un array vacío en el esquema de generación de chat; explicación exige tantas definiciones como filas. La validación backend continúa rechazando formatos incorrectos.

Prompt educativo revisión 3: ejemplo concreto de rango, encabezado sin resumen duplicado y coherencia de incertidumbre por fila. La evaluación E01 ahora exige reconocer los tres conceptos reales; antes podía aprobar aunque plaquetas quedara desconocida. No se reduce la exigencia para conseguir aprobación.

Compilación y 52 pruebas del asistente. Falta evaluación real en Windows; no se garantiza exactitud médica. Sin migración, nuevas dependencias ni regeneración de respuestas anteriores. Reversión: restaurar archivos desde commit anterior y compilar.
