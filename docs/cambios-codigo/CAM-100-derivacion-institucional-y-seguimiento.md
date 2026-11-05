# CAM-100 — Derivación institucional y seguimiento del paciente

## Alcance

Preparé derivación de una atención pendiente o iniciada a otro profesional habilitado de la misma clínica. El responsable selecciona destinatario, sucursal y especialidad, registra un motivo y confirma el cambio. El motivo es visible para el destinatario y el paciente. Una atención completada conserva su aprobación; no la reabro ni la convierto en derivación. La segunda opinión del paciente corresponde al siguiente incremento. (José Aránguiz)

Preparé Seguimiento de atención en el historial del paciente: muestra origen/destino, estado, institución, sucursal y motivo. La lectura exige propiedad del examen y no concede edición, acceso a otros pacientes ni permisos administrativos. Conservo los datos históricos aunque cambie la habilitación del equipo. El seguimiento tiene paginación explícita y no entrega teléfono, correo o domicilio personal en su respuesta. (José Aránguiz)

## Reglas y persistencia

La clínica, el documento, el paciente y el actor provienen de la atención autorizada y de la sesión, no del cuerpo del cliente. Exijo otro miembro de esa clínica, relación activa con sucursal/especialidad, credencial verificada con procedencia, motivo de 5 a 500 caracteres y confirmación. El catálogo de destinatarios es específico de la atención, paginado y auditado; no expone datos de contacto privados del profesional. (José Aránguiz)

En una sola transacción marco el origen como referred, creo la atención de destino requested y registro el vínculo de derivación. Conservo la atención anterior y sus auditorías; no sobrescribo responsable, contacto, procesamiento ni revisión. Reutilizo las restricciones y comprobaciones diferidas de 019 para impedir un origen/destino sin su vínculo. Bloqueo y revalido ambos ámbitos profesionales antes de confirmar. (José Aránguiz)

El requestId estable del formulario identifica el destino y la derivación. Serializo solicitudes del mismo origen y comparo actor, origen, versión, destinatario, sucursal, especialidad y motivo al repetir. Un reintento idéntico devuelve el recibo sin duplicar; el mismo identificador con otros datos produce conflicto. El recibo no concede acceso al destino al profesional anterior. (José Aránguiz)

Después del traslado, el anterior responsable no puede consultar ni descargar esa atención por su antiguo permiso; el destinatario la recibe en su bandeja y puede ver el motivo y el profesional de origen. Sigue existiendo una sola atención abierta por examen. No invoco modelos, reproceso el documento ni creo otra copia del archivo. La instantánea de contacto original se conserva; la sucursal de destino aparece como tal en el seguimiento. (José Aránguiz)

Añadí 024_clinic_referrals para ampliar la auditoría con referral_options. No añadí tablas clínicas: continúan 49 tablas base y la vista común, con 24 migraciones cuando se aplique. Preparé care-referral-app.sql con INSERT del vínculo y del antecedente de atención; no concedí actualización o borrado del historial. El servidor exige 024 al iniciar. (José Aránguiz)

## Comprobaciones

Comprobé compilación TypeScript y 815 pruebas backend en 58 suites, incluidas 26 nuevas de roles, entrada cerrada, identidad de sesión, lectura del propietario y verificadores. En PGlite ejecuté 49 comprobaciones y repetí las 49 con permisos de aplicación. Cubrí destinatario de otra clínica, autor distinto, mismo responsable, pertenencia suspendida, revisión obsoleta, confirmación ausente, rollback completo ante fallo del vínculo, repetición sin duplicados, pérdida de acceso del origen, recepción del motivo, conservación del contacto, historial del paciente y una cadena de derivación con una sola atención abierta. Forcé la comprobación de restricciones diferidas al finalizar. (José Aránguiz)

Comprobé aplicación, repetición, checksum y rollback de la migración. El motor aislado sustituye advisory locks y no acredita concurrencia real entre conexiones PostgreSQL 16. Preparé nueve pruebas Flutter nuevas y formateé ocho archivos Dart; flutter analyze y las 158 pruebas esperadas siguen pendientes en Windows, junto con respaldo, migración, permisos y recorrido. No considero formateo como ejecución Flutter ni afirmo haber probado S3/modelos reales en el verificador. (José Aránguiz)

## Confirmación de CAM-099 y continuidad

Registré 789 pruebas backend, análisis Flutter sin incidencias y 149 pruebas Flutter correctas. Tras el respaldo se aplicó 023 con 52 comprobaciones revertidas y permisos con COMMIT en 92 ms. La terminal informó requires_review con approved:false; el profesional aprobó, la atención quedó Completada y el paciente confirmó que ve los resultados revisados. Esa aprobación humana es independiente del indicador false de la extracción original. (José Aránguiz)

La prueba de derivación debe realizarse con otra atención ficticia pendiente o iniciada y otro profesional habilitado de la misma clínica; no debo modificar ni reabrir el examen ya aprobado para simularla. Mantengo pendientes segundas opiniones y cierre integrado/documentado de fase 7 antes de comparar y preparar el traspaso al develop actualizado del repositorio oficial. No modifiqué el oficial. (José Aránguiz)
