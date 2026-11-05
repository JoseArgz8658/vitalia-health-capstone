# CAM-020 — Corregir cierre del lector PDF en Windows

## Alcance autorizado
Corrección del lector PDF dentro de la creación y lo que conlleva autorizados por el usuario. No se modifica otro módulo.

## Evidencia
El usuario obtuvo -1073741819 tras RUNS en Jest, sin resumen. Es 0xC0000005. Un reporte en PDF.js describe ese código al cargar pdfjs-dist 5.x en worker_threads en Windows. Causa probable, no confirmada con volcado nativo.
https://github.com/mozilla/pdf.js/issues/21934

## Cambio
reader.ts usa child_process.fork en lugar de worker_threads. reader-worker.ts conserva su ruta, pero ahora es entrada de un proceso Node y recibe bytes por IPC. El padre espera cierre correcto, informa reader_error ante un cierre anormal y termina lecturas que exceden 15 segundos. Heap limitado a 128 MiB, no memoria total. No cambia biblioteca, archivos originales, datos o criterios.

## Verificación
Compilación y 18 pruebas aprobadas: ocho del lector (dos nuevas de cierre anormal y tiempo excedido) y diez de IA. No se dispone de Windows aquí; debe repetirse allí y comprobar LASTEXITCODE 0. No se afirma que el fallo original esté resuelto en Windows hasta esa comprobación.

## Reversión
Restaurar reader.ts, reader-worker.ts, prueba y guía al commit anterior. La reversión recuperaría el mecanismo de hilos relacionado con el fallo observado; no es recomendable antes de resolverlo.
