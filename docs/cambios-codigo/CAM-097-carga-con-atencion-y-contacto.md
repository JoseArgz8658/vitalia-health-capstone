# CAM-097 — Carga con atención elegida y contacto confirmado

## Alcance

Conecté la carga del examen con el catálogo de CAM-096. Organicé el formulario en cuatro pasos dentro de la misma pantalla: ubicación/contacto, atención, archivo y revisión final. El paciente elige explícitamente clínica, sucursal, especialidad y profesional; no asigno un responsable automáticamente ni interpreto las opciones como horas reservables. La pantalla del profesional para gestionar estas nuevas atenciones corresponde al siguiente incremento. (José Aránguiz)

## Ubicación y contacto

Precargo teléfono y domicilio guardados. Cuando todavía no hay comuna de residencia guardada, uso la comuna preferida del perfil como sugerencia. Exijo al envío comuna de residencia, calle, número o S/N, teléfono, comuna de atención y confirmación final. Obtengo el correo desde la cuenta autenticada en el servidor; no acepto correo, propietario ni rol indicados en el cuerpo del cliente. No equiparo correo registrado a correo verificado. Para utilizar la carga debo tener primero mis datos personales registrados. No completo datos históricos ficticios ni bloqueo el inicio de sesión por domicilios vacíos. (José Aránguiz)

Separo residencia y zona de atención: buscar en otra comuna no cambia el domicilio. Incluí la opción explícita de guardar domicilio/teléfono en el perfil; puedo desmarcarla para utilizarlos solo en este envío. Al guardar en el perfil comparo su revisión para evitar sobrescribir cambios concurrentes. Conservo la comuna preferida anterior y registro la residencia en un campo separado. Puedo comprobar la precarga al volver a abrir el formulario; este incremento no añade edición de domicilio a la pantalla general de Mi perfil. (José Aránguiz)

## Persistencia y permisos

Añadí 021_care_upload: domicilio opcional en la persona, indicador care_flow en documentos y una tabla de contacto confirmado por examen. La base pasa de 46 a 47 tablas y de 20 a 21 migraciones cuando se aplique. El contacto conserva una instantánea de teléfono/correo/domicilio/zona ligada a la atención inicial y al propietario del documento; no se modifica posteriormente ni cambia si edito mi perfil. (José Aránguiz)

Valido la elección antes de reservar/subir el archivo y la revalido dentro de la transacción que confirma documento, atención inicial, contacto y auditoría. Incluí un bloqueo acotado de los registros institucionales y de credenciales para impedir que se suspendan o eliminen relaciones mientras se confirma la elección. La función SECURITY DEFINER solo bloquea/valida una selección, tiene referencias de esquema explícitas, search_path fijo y EXECUTE revocado a PUBLIC; el permiso específico se concede a vitalia_app. Así no concedo UPDATE de catálogos/asociaciones únicamente para leerlos con bloqueo. (José Aránguiz)

Ante un fallo revierto la transacción, marco la reserva fallida e intento compensar el objeto en S3 utilizando el mecanismo existente. No mantengo la transacción abierta durante S3. Conservo el aviso de actualizar el historial antes de repetir si se pierde la respuesta; la carga existente todavía no garantiza idempotencia frente a reintentos de red. (José Aránguiz)

Protegí el circuito nuevo: las consultas, descargas y revisiones basadas en asignaciones generales excluyen documentos care_flow. Una asignación antigua de paciente no permite abrir un examen enviado a otro profesional. Los documentos históricos conservan el comportamiento anterior. Impedí bajar el indicador care_flow y añadí una comprobación diferida que impide confirmar un documento de este circuito sin contacto/elección asociados. No habilité todavía la bandeja clínica por examen, derivaciones ni segundas opiniones; estos exámenes quedan registrados para el siguiente incremento. (José Aránguiz)

La API requiere 021 al iniciar; no debe reiniciarse con este cambio antes de completar la migración y los permisos. Preparé care-upload-app.sql con permisos acotados y sin conceder UPDATE/DELETE del contacto ni privilegios de revisión clínica nuevos. No modifiqué el repositorio oficial. (José Aránguiz)

## Validación

Comprobé la compilación TypeScript y 734 pruebas backend en 55 suites, incluidas 28 pruebas nuevas de entrada cerrada, sesión, roles, revisiones de perfil, carga/compensación y verificadores. Ejecuté 34 comprobaciones SQL aisladas y repetí las 34 usando permisos de aplicación en las operaciones del servicio. Incluí cambio de habilitación entre preflight y confirmación, fallo de inserción del contacto, reversión del perfil, aislamiento frente a asignaciones anteriores, contacto inmutable, imposibilidad de bajar care_flow y documento nuevo sin contacto. Los datos sintéticos se revirtieron. También comprobé aplicación, repetición, checksum y rollback de DDL. (José Aránguiz)

El motor aislado PGlite sustituye advisory locks y no demuestra concurrencia real entre conexiones de PostgreSQL 16. El verificador nativo, la migración, los permisos y el recorrido local siguen pendientes. Preparé nueve pruebas Flutter y adapté una existente; apliqué el formateador Dart como comprobación de sintaxis. No dispongo de Flutter en este entorno, por lo que no afirmo haber ejecutado flutter analyze, las 131 pruebas esperadas ni una revisión visual real. (José Aránguiz)

## Continuidad

Registré la confirmación recibida de CAM-096: 706 pruebas backend aprobadas en Windows y 28 comprobaciones del catálogo correctas en PostgreSQL, con datos sintéticos revertidos. Mantengo fuera del MVP la comprobación semántica de que el archivo es un examen, según lo acordado. No introduje reserva de horas, notificaciones de emergencia ni comprobación externa de registros médicos. Al completar la fase 7 prepararé la integración con el develop actualizado del repositorio oficial, siguiendo las reglas acordadas. (José Aránguiz)

## Confirmación del entorno local recibida

Registré 734 pruebas backend aprobadas en 55 suites, análisis Flutter sin incidencias y 131 pruebas Flutter, con código 0. Tras el respaldo, 021 se aplicó con 34 comprobaciones correctas y datos sintéticos revertidos. Los permisos finalizaron con COMMIT en 82 ms. El paciente confirmó que el examen quedó guardado y que el formulario funcionó. La extracción no se ejecutó; queda pendiente hasta el recorrido integrado de procesamiento/revisión. (José Aránguiz)
