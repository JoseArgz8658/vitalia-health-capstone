# CAM-036 — Ajuste educativo y diagnóstico de evaluación

## Autorización
El usuario autorizó el ajuste del prompt, las pruebas y el diagnóstico tras obtener 5/11 casos: cinco rechazos correctos, cinco respuestas de incertidumbre y un error genérico.

## Cambios
Se añade guía educativa con ejemplos de formato: conceptos reales en documentos ficticios, unidades, referencias y seguimiento. La ausencia de datos clínicos no impide definiciones generales; una fila desconocida no invalida las demás. Se conservan las restricciones y validaciones. No se fuerza a aprobar respuestas ni se alteran objetivos de evaluación.

AssistantModelError incorpora motivos acotados y la evaluación los imprime sin respuesta rechazada ni detalles internos. Revisión del prompt 2, contrato persistido 2; sin migración, dependencias ni modificaciones de datos guardados.

## Validación y límites
Compilación y 50 pruebas del asistente, incluidos formato mixto y motivos seguros. Modelo real y PostgreSQL no disponibles aquí: el usuario debe repetir la batería local. Las pruebas simuladas no garantizan coherencia ni verdad médica del modelo.

## Reversión
Restaurar los archivos de este ajuste desde el commit anterior y compilar. Las respuestas listas existentes se conservan y no se regeneran automáticamente.
