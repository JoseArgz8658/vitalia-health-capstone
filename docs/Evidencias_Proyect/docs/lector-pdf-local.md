# Lector aislado de PDF con texto

Lee bytes de un PDF local con pdf-parse 2.4.5 (basado en PDF.js), en un proceso Node separado. No consulta S3, PostgreSQL ni Ollama; no añade rutas a la aplicación. La dependencia extrae texto y no hace OCR. Los documentos de prueba son ficticios y se incluyen codificados en backend/test/pdf-fixtures.json.

## Windows
Desde la raíz, entrar al backend y actualizar dependencias:

```powershell
cd backend
npm ci
npm test -- --runTestsByPath test/pdf-reader.test.cjs test/ai-extraction.test.cjs
node dist/pdf/check.js
```

No requiere Ollama, servidor, emulador ni .env. El comando final lee tres PDFs ficticios incluidos y muestra:
- texto: text_ready con texto y una página.
- imagen: needs_ocr, sin texto entregado.
- protegido: rejected con password_required.

Compartir la salida completa. No añadir argumentos ni archivos médicos reales a esta comprobación.

## Contrato y límites
readPdfText recibe Uint8Array y devuelve status, text, pageCount e incidents. Firma %PDF- y tamaño hasta 10 MiB; máximo diez páginas; texto hasta 12000 bytes. Sin truncar la salida para hacerla caber. El proceso lector se termina si excede quince segundos. Su heap de JavaScript se limita a 128 MiB; esto no limita toda la memoria nativa y no constituye aislamiento de seguridad para archivos hostiles. Un cierre anormal se informa como reader_error sin aprobar la lectura.

Si alguna página carece de letras o números extraíbles, el resultado completo es needs_ocr y text es null: no se entrega una extracción parcial como si cubriera el documento. Una página en blanco también requiere comprobación; este estado no demuestra que exista una imagen escaneada. El OCR está pendiente.

text_ready solo indica disponibilidad de texto: no garantiza orden de lectura, fidelidad visual o cobertura de imágenes en páginas mixtas. Un PDF con algo de texto y una imagen del examen puede pasar la detección y omitir contenido de esa imagen. Tablas complejas y fuentes pueden alterar orden, espacios o codificación. En el PDF ficticio, el signo micro µ se extrajo como letra griega μ; no se realiza sustitución automática. El original debe conservarse para revisión.

Se rechazan PDFs protegidos, dañados, excedidos o no legibles. No se intenta desbloquear. El número de páginas puede ser null cuando no se pudo abrir el PDF. La lectura no ejecuta JavaScript del documento; isEvalSupported se desactiva. No hay integración ni aprobación profesional.

El módulo consume bytes y nunca recibe URL como entrada. pdf-parse declara soporte para Node 20.16+ de la rama 20 o Node 22.3+; usar Node 24 en el equipo actual. npm ci instala también dependencias transitivas y opcionales indicadas por el lockfile.

## Referencia
https://github.com/mehmet-kozan/pdf-parse

## Corrección de cierre en Windows
El usuario obtuvo código -1073741819 (0xC0000005) durante Jest. Existe un reporte de PDF.js con ese mismo fallo al cargar versiones 5.x en worker_threads de Windows. Es una causa probable, no una confirmación mediante diagnóstico nativo en este equipo. El lector ahora usa un proceso separado y espera su cierre correcto. No cambia la dependencia ni los criterios de lectura.

Para comprobar, desde backend:
```powershell
npm test -- --runTestsByPath test/pdf-reader.test.cjs test/ai-extraction.test.cjs
$LASTEXITCODE
node dist/pdf/check.js
$LASTEXITCODE
```
Se esperan 18 pruebas aprobadas y código 0 en ambos comandos.

Referencia del reporte: https://github.com/mozilla/pdf.js/issues/21934
