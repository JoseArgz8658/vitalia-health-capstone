# CAM-018 — Módulo aislado de extracción y validación

## Autorización
El usuario autorizó crear módulo aislado y documentación el 1 de octubre de 2026.

## Archivos nuevos
backend/src/ai/contract.ts, prompt.ts, local-extractor.ts y check.ts; backend/test/ai-extraction.test.cjs; guía y avance. Sin modificaciones de código existente ni dependencias nuevas. Usa Zod disponible.

Conserva respuesta original, detecta JSON/estructura inválidos, fecha inválida y campos no extraídos. No corrige números o unidades ni aprueba resultados. Ollama local con límites de entrada, respuesta y tiempo; transporte inyectable para pruebas.

## Verificación
npm test -- --runTestsByPath test/ai-extraction.test.cjs: compilación correcta y diez pruebas aprobadas. Pruebas cubren preservación, calendario, campos independientes, respuestas inválidas, petición local, límites y errores de servicio. Llamada real a Ollama pendiente en Windows.

## Reversión
Eliminar los archivos nuevos y recompilar. No se modifican rutas del servidor, base de datos, S3 ni Flutter.
