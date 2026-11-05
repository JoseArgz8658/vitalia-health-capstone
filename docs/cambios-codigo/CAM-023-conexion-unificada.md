# CAM-023 — Conexión unificada de lectura, OCR e IA

## Autorización
El usuario autorizó crear conexión unificada, pruebas y documentación el 1 de octubre de 2026.

## Cambios nuevos
backend/src/ai/document-extraction.ts y check-documents.ts; backend/test/document-extraction.test.cjs; guía y avance. Sin cambios a código existente, dependencias o configuración externa.

PDF text_ready usa lectura directa; needs_ocr usa OCR. Imágenes usan OCR. Documentos rechazados, vacíos o excedidos no llegan al modelo. Conserva texto, lectura, OCR e IA; approved false. Errores de servicio conservan la lectura disponible y no exponen detalles.

## Verificación
47 pruebas aprobadas en cinco suites; doce nuevas de selección, bloqueo y conservación. Incluye PDF escaneado real procesado por OCR con extractor simulado y PDF protegido real detenido antes de IA. Compilación TypeScript correcta. La ejecución con Ollama real de cinco documentos requiere comprobación Windows.

Límite conocido: texto OCR puede contener unidades incorrectas pese a confianza alta; lectura directa no detecta todas las imágenes de PDF mixtos. No se acredita precisión clínica.

## Reversión
Eliminar archivos nuevos y recompilar. Sin cambios de datos, dependencias o rutas.
