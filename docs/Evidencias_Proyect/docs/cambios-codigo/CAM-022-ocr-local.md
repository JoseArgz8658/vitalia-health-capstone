# CAM-022 — OCR aislado local

## Autorización
El usuario respondió continuar a la propuesta de implementar OCR, dependencias, pruebas y guía el 1 de octubre de 2026.

## Cambios
Dependencias fijas tesseract.js 7.0.0 y @tesseract.js-data/spa 1.0.0 con lockfile. Archivos nuevos backend/src/ocr/contract.ts, reader.ts, reader-process.ts y check.ts; pruebas y fixtures; guía y avance. Datos de idioma locales, sin descarga en ejecución.

OCR se ejecuta en proceso separado. PDF renderizado por la biblioteca ya instalada. Límites de tamaño, resolución, páginas, texto y tiempo. Texto original sin correcciones y approved false. No modifica módulos existentes, rutas, cuentas, datos o configuración AWS.

## Verificación
OCR real de tres fixtures PNG/JPEG/PDF, con revisión visual del PDF. Nueve pruebas OCR aprobadas, incluidos documentos protegidos/excedidos, imagen en blanco, confianza, lectura parcial, cierre anormal y tiempo excedido. Suite completa: 150 pruebas, 23 suites aprobadas. Windows pendiente.

Limitación observada: µL convertido en uL incluso con confianza alta. Las cifras principales se conservaron en los ejemplos; no se afirma fidelidad clínica ni integración.

## Reversión
Restaurar package.json y lockfile al commit anterior, npm ci y eliminar archivos nuevos. Sin cambios de base de datos o documentos guardados.
