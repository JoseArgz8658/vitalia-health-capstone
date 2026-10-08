# OCR local aislado — fase 5

Reconocimiento de PNG/JPEG y páginas de PDF con Tesseract.js 7.0.0 y datos locales de español @tesseract.js-data/spa 1.0.0. Se instalan con npm ci. No descarga idiomas durante el reconocimiento, no consulta servicios de OCR externos y no envía el texto a Ollama en esta entrega.

## Windows
Desde backend, tras cambiar a la rama fase-5/ocr-local:

```powershell
npm ci
npm test -- --runTestsByPath test/ocr.test.cjs
$LASTEXITCODE
node dist/ocr/check.js
$LASTEXITCODE
```

Se esperan nueve pruebas aprobadas y código 0. El comando check reconoce tres documentos ficticios incluidos: PNG, JPEG y PDF escaneado, con los mismos datos. Deben devolver requires_review y approved false. No necesita backend iniciado, emulador, .env ni Ollama. Compartir salida completa.

## Resultado y límites
readOcr recibe bytes y formato png, jpeg o pdf. Devuelve texto, páginas con texto original y confianza, incidencias y approved siempre false. Toda salida utilizable queda requires_review, nunca aprobada. Una página sin texto impide entregar el documento completo como texto listo; las páginas reconocidas pueden conservarse para diagnóstico.

Límites: 10 MiB, tres páginas PDF, cuatro millones de píxeles por imagen/página, 12000 bytes de texto completo y 60 segundos. PDFs se renderizan secuencialmente a 1600 píxeles de ancho usando pdf-parse. Firma y dimensiones declaradas de imágenes se comprueban antes de decodificar. Proceso Node separado, heap de 256 MiB; no limita toda la memoria nativa ni constituye un entorno seguro frente a archivos hostiles. No hay control global de concurrencia porque aún no existe endpoint.

Se rechazan PDFs protegidos, documentos dañados, límites excedidos o fallos del proceso. El texto no se trunca ni se corrige automáticamente. El PDF con texto también puede pasarse explícitamente a este lector, pero no hay selección automática de método ni cambio en la conexión PDF→IA anterior.

La confianza de Tesseract es un indicador técnico, NO probabilidad de exactitud ni garantía clínica. Valor menor de 70 agrega low_confidence; una confianza mayor tampoco aprueba datos. El criterio 70 es inicial, no calibrado.

## Error observado en la muestra
El original muestra µL. Las tres lecturas locales produjeron uL, con confianza aproximada 89–90. Se mantiene el resultado tal como lo devuelve OCR, sin reemplazar caracteres ni completar unidades. Las pruebas de muestra comprueban cifras y fecha, no acreditan fidelidad de todas las unidades. El profesional debe comparar contra la imagen original antes de aprobar. El OCR puede alterar separadores, cifras, signos, nombres, orden y tablas.

Los fixtures en backend/test/ocr-fixtures.json contienen solo documentos ficticios codificados en base64. El check no admite rutas externas ni datos reales. No modifica PostgreSQL, S3, Flutter o cuentas. La creación de cuentas privilegiadas sigue pendiente.

## Referencias
https://github.com/naptha/tesseract.js
https://github.com/naptha/tessdata
https://github.com/mehmet-kozan/pdf-parse
