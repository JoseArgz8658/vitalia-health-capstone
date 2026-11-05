# Documentos: persistencia de metadatos

Primer paso de la fase 4. Solo archivos nuevos; no añade rutas ni cambia Flutter.
Contenido previsto en S3 privado, pendiente de integración.
La tabla guarda nombre, tipo, fecha, MIME, tamaño, propietario y clave interna del objeto.
Estados pending/stored/failed: reservar metadatos no implica almacenar contenido.
Las consultas de paciente filtran siempre por su identidad y solo muestran stored.
No están habilitados accesos de profesional: requieren relaciones de autorización posteriores.
La clave del objeto no usa el nombre recibido. MIME y tamaño en este módulo son metadatos: la carga futura deberá comprobar el contenido real.
Límite inicial interno: PDF/JPEG/PNG y 10 MiB; sujeto a validación de requisitos de carga.

## Desde backend
```powershell
npm ci
npm run check
npm test
node --env-file=.env dist/database/check.js
node --env-file=.env dist/database/migrate-documents.js
node --env-file=.env dist/database/verify-documents.js
```

PostgreSQL debe estar activo. No cambies .env.
La verificación usa dos pacientes sintéticos y comprueba que uno no vea ni confirme documentos del otro.
Todos los datos de prueba se revierten. No sube archivos a S3 ni deja registros permanentes.
La migración crea una tabla permanente y es repetible; no borres tablas para reintentar.
