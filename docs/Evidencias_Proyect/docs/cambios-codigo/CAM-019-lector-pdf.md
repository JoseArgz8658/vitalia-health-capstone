# CAM-019 — Lectura local de PDF con texto

## Autorización
El usuario autorizó crear el lector PDF y lo que conlleva, incluidas pruebas y dependencia, el 1 de octubre de 2026.

## Cambios
Dependencia fija pdf-parse 2.4.5 en backend/package.json y package-lock.json. Sin cambios a versiones existentes del lockfile. Archivos nuevos en backend/src/pdf: reader, reader-worker y check. Pruebas y fixtures ficticios en backend/test. Guía y avance.

Lectura por página en worker; rechaza documentos excedidos, dañados y protegidos. Cualquier página sin texto aprovechable marca needs_ocr sin devolver una parte del documento. No modifica rutas, bases de datos o configuración AWS. No implementa OCR ni conecta la extracción al modelo.

## Verificación
Compilación y comprobación real de tres PDFs: texto extraído, imagen needs_ocr, protegido rejected. Seis pruebas del lector más diez del módulo IA aprobadas. Suite backend completa: 131 pruebas, 21 suites aprobadas. PDFs ficticios renderizados y revisados visualmente. Windows pendiente.

No se afirma fidelidad total: la codificación micro µ se extrajo como μ en la muestra. Worker y límites no garantizan aislamiento de seguridad ni cobertura de imágenes en PDFs mixtos.

## Reversión
Restaurar package.json y lockfile al commit anterior, ejecutar npm ci y eliminar archivos nuevos de lector/pruebas/documentación. Sin cambios de datos.
