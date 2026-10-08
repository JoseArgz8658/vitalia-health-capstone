# CAM-014 — Evaluador local de extracción

## Autorización
El usuario autorizó crear archivos nuevos de evaluación y su guía el 1 de octubre de 2026.

## Cambios y consecuencias
Se agregan scripts/ia/evaluar-extraccion.mjs, casos-extraccion.json y evaluar-extraccion.test.mjs, docs/evaluar-ia-local.md y avance fase-5-01. No se modifica código existente. Node sin dependencias adicionales llama a Ollama local con esquema JSON y casos ficticios. Compara la extracción sin corregirla y deriva campos ausentes desde null. Guarda informes fuera del repositorio.

## Verificación
node --check scripts/ia/evaluar-extraccion.mjs y node --test scripts/ia/evaluar-extraccion.test.mjs. Seis pruebas del evaluador, incluidas fechas, los errores observados, alteración de valores y fallos de transporte. La ejecución del modelo real queda pendiente en Windows; no está instalado en el entorno del agente.

## Reversión
Eliminar los archivos nuevos de esta entrega desde Git y, si se desea, los informes temporales locales. No hay migraciones ni modificaciones de datos o configuración de la aplicación.
