# Revisión por atención — CAM-099

Preparé cotejo y aprobación del examen por su responsable, con lectura posterior del paciente y compatibilidad con las funciones educativas existentes. No considero cerrada la fase 7. (José Aránguiz)

## Validación local y esquema

1. Actualizo fase-7/03-atencion-examen. En backend ejecuto npm test: espero 789 pruebas en 57 suites. En apps/vitalia ejecuto flutter analyze y flutter test: espero 149 pruebas, pendientes de ejecución en Windows.
2. Detengo el backend y guardo vitalia_dev_antes_023.
3. Como postgres, con variables temporales restauradas al terminar, ejecuto dist/database/migrate-care-review.js y dist/database/verify-care-review.js. Espero migración aplicada y Revisión por examen: 52 comprobaciones correctas. Datos sintéticos revertidos.
4. En pgAdmin, como postgres sobre vitalia_dev, ejecuto todo backend/database/permissions/care-review-app.sql. Espero COMMIT. Compruebo 49 tablas BASE TABLE y 23 migraciones; la vista vitalia_current_approved_reviews se cuenta por separado.
5. Reinicio backend y Flutter. La API exige 023 para iniciar. No publico .env ni almaceno credenciales administrativas.

## Recorrido integrado, después de la aplicación

Utilizo el examen ficticio ya guardado y la cuenta paciente propietaria. Entonces solicito su procesamiento desde la pantalla del paciente, con los servicios locales y el procesador de cola del proyecto en funcionamiento. Espero a que termine como pendiente de revisión profesional. Si falla o queda en espera, reviso los servicios/worker y el mensaje mostrado antes de avanzar; no fuerzo estados ni invento una extracción. (José Aránguiz)

Ingreso con el profesional responsable y abro la atención iniciada. Pulso Actualizar revisión: debe aparecer el formulario solo cuando haya extracción válida y la atención esté En atención. Descargo y cotejo el documento original. Recorro datos del informe, resultados y confirmación; verifico que avanzar y retroceder conserve lo editado. Corrijo exclusivamente datos comprobados y justifico correcciones o ausencias. (José Aránguiz)

Confirmo el cotejo y pulso Aprobar revisión y completar atención. Compruebo estado Completada, revisión guardada con autor/fecha y original conservado. Reabrir no debe habilitar edición de la aprobación. Como paciente, consulto los resultados revisados; las explicaciones y el chat educativos conservan su separación y advertencias. Su lectura de estado usa la misma revisión aprobada, sin confundirla con la extracción preliminar. (José Aránguiz)

Compruebo que otra cuenta profesional o administrador no pueda consultar/aprobar esta revisión. No considero validada una integración real con Ollama por las pruebas sintéticas del verificador. Tampoco repito una aprobación modificada para reemplazar resultados: cada aprobación es inmutable. (José Aránguiz)

Derivaciones y segundas opiniones continúan en incrementos posteriores, conservando estas revisiones. El oficial permanece sin cambios hasta el cierre y preparación del traspaso acordado. (José Aránguiz)
