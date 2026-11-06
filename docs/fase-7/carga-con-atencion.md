# Carga de examen con atención — CAM-097

Preparé el formulario por pasos y la persistencia de elección/contacto. Este bloque registra la atención inicial solicitada; la bandeja del profesional y sus acciones se implementan después. No considero cerrada la fase 7. (José Aránguiz)

## Validación y aplicación local

1. Actualizo fase-7/03-atencion-examen y ejecuto npm test en backend: espero 734 pruebas en 55 suites. En apps/vitalia ejecuto flutter analyze y flutter test: espero 131 pruebas; todavía no las he ejecutado en este entorno.
2. Detengo el backend y guardo vitalia_dev_antes_021.
3. Como postgres, con variables temporales restauradas al terminar, ejecuto migrate-care-upload.js y verify-care-upload.js desde dist/database. Espero migración aplicada y 34 comprobaciones correctas con datos sintéticos revertidos.
4. En pgAdmin, como postgres sobre vitalia_dev, ejecuto todo backend/database/permissions/care-upload-app.sql. Espero COMMIT.
5. Compruebo 47 tablas, 21 migraciones y 021_care_upload registrada; reinicio el backend y Flutter para el recorrido.

Mantengo el procedimiento de credenciales temporales de las migraciones anteriores. No publico .env ni guardo contraseñas administrativas en el proyecto. El servidor requiere 021 para iniciar. (José Aránguiz)

## Recorrido del paciente

Utilizo cuentas y documentos ficticios. Necesito una sucursal activa con comuna, un profesional activo vinculado a esa sucursal y especialidad, concesión profesional activa y credencial verificada con procedencia. No creo Medicina general ficticia ni infiero una especialidad por IA. Si no hay opciones en la comuna, puedo elegir otra zona. (José Aránguiz)

- Abro Subir examen y compruebo la precarga del perfil. Completo comuna de residencia, calle, número o S/N y teléfono; el correo corresponde a la cuenta y no se puede reemplazar desde este formulario.
- Decido si guardar domicilio/teléfono en mi perfil. El consentimiento es visible; si lo desmarco, solo quedan asociados al examen.
- Confirmo si buscar en mi comuna o en otra zona. Selecciono clínica, sucursal, especialidad y profesional. Si hay más de 30 opciones, uso Cargar más opciones de esta comuna.
- Completo nombre/tipo/fecha y adjunto PDF/JPEG/PNG de hasta 10 MiB. Retrocedo y compruebo que se conserven los datos.
- Reviso el resumen y marco la confirmación. Solo entonces envío. Compruebo que el documento aparezca en el historial.
- Si guardé el perfil, vuelvo a abrir el formulario y compruebo que reaparezcan domicilio/teléfono. La zona de búsqueda no debe haber cambiado el domicilio ni la comuna preferida del perfil.

Cuando el perfil cambie en otra sesión, vuelvo al paso de contacto y utilizo Volver a cargar mis datos del perfil antes de confirmar nuevamente. Si cambia la selección profesional, regreso a atención y repito la búsqueda. Si se pierde la respuesta de carga, actualizo el historial antes de repetir el envío. (José Aránguiz)

## Protección y continuidad

Compruebo que un profesional con asignación antigua de paciente no pueda ver, descargar ni revisar el examen enviado por este circuito. Los exámenes históricos conservan su acceso anterior. La bandeja del responsable por examen está pendiente y no debe confundirse con la pantalla heredada. No transfiero el repositorio ni doy por cerrada la fase hasta completar los incrementos clínicos restantes y su validación. (José Aránguiz)
