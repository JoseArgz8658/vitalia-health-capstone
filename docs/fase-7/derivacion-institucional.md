# Derivación institucional — CAM-100

Preparé traslado auditado dentro de la misma clínica y seguimiento del paciente. La segunda opinión sobre una atención completada sigue pendiente; no debe confundirse con esta derivación de una atención aún abierta. (José Aránguiz)

## Validación local

1. Actualizo fase-7/03-atencion-examen y ejecuto npm test en backend: espero 815 pruebas en 58 suites. En apps/vitalia ejecuto flutter analyze y flutter test: espero 158 pruebas, pendientes de validación en Windows.
2. Detengo backend y guardo vitalia_dev_antes_024.
3. Como postgres, con credenciales temporales restauradas al terminar, ejecuto dist/database/migrate-care-referral.js y dist/database/verify-care-referral.js. Espero migración aplicada y Derivación institucional: 49 comprobaciones correctas. Datos sintéticos revertidos.
4. En pgAdmin, como postgres en vitalia_dev, ejecuto todo backend/database/permissions/care-referral-app.sql. Espero COMMIT. Compruebo 49 tablas BASE TABLE y 24 migraciones; la vista se cuenta aparte.
5. Reinicio backend y Flutter. No inicio la API nueva antes de aplicar la migración y los permisos.

## Preparación del recorrido

Necesito otra atención ficticia pendiente o En atención y dos profesionales habilitados de la misma clínica. Cada destinatario requiere sucursal/especialidad activas y credenciales verificadas; aceptar una invitación por sí solo no basta. Si no hay otro destinatario, la lista vacía debe explicarlo y no permitir confirmar. No altero el examen ya aprobado ni invento pertenencias para probar. (José Aránguiz)

## Recorrido

Como responsable abro la atención abierta y pulso Derivar dentro de la clínica. Selecciono otro profesional y compruebo su especialidad, sucursal y dirección. Registro un motivo apropiado para ser leído por el paciente y el destinatario. Marco la confirmación y envío. Debe aparecer el recibo; vuelvo a mis atenciones y el origen ya no debe darme acceso a ese documento. (José Aránguiz)

Como destinatario compruebo la atención Pendiente de iniciar, el mismo examen/contacto y el motivo/profesional de origen. Puedo comenzar la atención y continuar su revisión. Como paciente abro Seguimiento de atención y compruebo el origen Derivada y el nuevo destino; no existe una reserva de hora ni una notificación automática por correo en este cambio. (José Aránguiz)

La derivación no solicita extracción ni duplica el archivo. Para una prueba de traslado basta con comprobar recepción e inicio; el procesamiento puede probarse después según el estado real del documento y el recorrido de CAM-099. Una atención completada no muestra este botón: la solicitud de segunda opinión es una función posterior. (José Aránguiz)
