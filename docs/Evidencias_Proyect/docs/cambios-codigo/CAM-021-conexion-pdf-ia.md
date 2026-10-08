# CAM-021 — Conexión aislada PDF e IA

## Autorización
El usuario autorizó crear conexión aislada, pruebas y documentación el 1 de octubre de 2026.

## Archivos nuevos
backend/src/ai/pdf-extraction.ts y check-pdf.ts; backend/test/pdf-extraction.test.cjs; guía y avance. Sin modificaciones de código existente ni dependencias nuevas.

Conserva lectura, salida IA e incidencias; approved siempre false. Estados sin texto no invocan modelo. Errores de servicio no exponen mensajes internos ni hacen desaparecer el texto leído. CLI utiliza únicamente PDF ficticios incluidos.

## Verificación
Compilación TypeScript y 26 pruebas aprobadas: ocho nuevas, ocho del lector y diez IA. Incluye lectura de PDFs reales ficticios con transporte Ollama simulado, bloqueos para imagen/protegido, JSON inválido, texto vacío y servicio fallido. Llamada real a Ollama pendiente en Windows.

## Reversión
Eliminar los archivos nuevos y recompilar. Sin cambios de datos, permisos, backend HTTP, almacenamiento o Flutter.
