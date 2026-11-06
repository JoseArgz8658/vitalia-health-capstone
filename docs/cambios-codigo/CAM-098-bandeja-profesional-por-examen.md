# CAM-098 — Bandeja del profesional responsable

## Alcance

Preparé la bandeja de atenciones por examen para el profesional elegido por el paciente. Incorporé un acceso visible desde el espacio profesional, un listado paginado de pendientes/iniciadas, detalle con contacto confirmado, descarga adjunta del documento y la acción Comenzar atención. No modifiqué el acceso de los documentos históricos ni habilité procesamiento, aprobación de resultados, derivaciones o segundas opiniones en este incremento. (José Aránguiz)

## Autorización por examen

La API utiliza la cuenta de la sesión profesional y el identificador de atención. No acepta identidad de paciente/profesional, rol o clínica proporcionados por el cliente. Exijo que la cuenta corresponda al responsable, con pertenencia, clínica, sucursal, especialidad y concesión profesional activas y credencial con procedencia coherente. Una jefatura o una asignación general de paciente no amplía el acceso a otros exámenes. Las atenciones canceladas/derivadas y las relaciones inhabilitadas quedan fuera de esta bandeja. El historial de atenciones completadas requerirá el incremento de revisión posterior. (José Aránguiz)

En detalle e inicio bloqueo la atención y revalido la selección con el mecanismo acotado de 021. No expongo datos si falla la auditoría. El listado devuelve nombre del paciente, metadatos del examen e institución, sin teléfono, correo ni domicilio. El detalle autorizado entrega la instantánea confirmada del contacto, separando domicilio y zona de atención; no presenta ese dato como una verificación externa. (José Aránguiz)

La descarga no expone URL de S3 ni permite elegir una clave. Compruebo ruta, tamaño y tipo técnico del archivo, libero la transacción durante su lectura y revalido autorización/estado antes de entregarlo. La respuesta usa attachment, nosniff y no-store. Si se pierde la habilitación durante la lectura, no entrego el archivo. No envío mensajes ni hago llamadas al paciente desde esta función. (José Aránguiz)

## Estado y auditoría

Comenzar atención cambia requested a active, incrementa revisión y conserva el actor en la auditoría de atención existente. Exijo revisión esperada y rechazo campos adicionales. Un reintento de la misma transición ya aplicada responde como repetición sin duplicar el cambio ni su auditoría; una revisión incompatible requiere actualizar. No solicito extracción ni genero resultados al iniciar una atención. (José Aránguiz)

Añadí 022_care_inbox con una tabla inmutable de accesos list/view/download, ligada a actor y atención cuando corresponde. No almaceno contenido médico ni datos de contacto en esa auditoría. Cuando se aplique, la base tendrá 48 tablas y 22 migraciones. Preparé care-inbox-app.sql con INSERT de auditoría y UPDATE acotado de estado/actor/revisión de atención. No concedí edición ni borrado de la auditoría ni del contacto. El servidor exige la tabla de 022 al iniciar. (José Aránguiz)

## Comprobaciones

Comprobé compilación TypeScript y 763 pruebas backend en 56 suites, incluidas 29 nuevas de sesión/rol, filtros, identidad de sesión, descarga adjunta, errores y verificadores. En PGlite ejecuté 52 comprobaciones reversibles y repetí las 52 con permisos de aplicación: acceso del responsable, rechazo de otra jefatura incluso con asignación general, suspensión/credencial alterada, descarga revalidada tras S3 simulado, inicio repetible sin duplicados, reversión de estado/auditoría ante fallo y cancelación. Comprobé que iniciar no cree procesamiento. Probé además aplicación, repetición, checksum y rollback de la migración. El almacenamiento fue sintético; no afirmo haber probado S3 real ni concurrencia entre conexiones PostgreSQL 16 en este entorno aislado. (José Aránguiz)

Preparé nueve pruebas Flutter y formateé seis archivos Dart. Todavía debo ejecutar flutter analyze y las 140 pruebas esperadas en Windows, aplicar respaldo/migración/permisos y confirmar el recorrido nativo. No equiparo formateo con análisis, ejecución o revisión visual. (José Aránguiz)

## Evidencia recibida y continuidad

Registré CAM-097 con 734 pruebas backend, análisis sin problemas y 131 pruebas Flutter en Windows; respaldo previo; 021 aplicada con 34 comprobaciones correctas revertidas; permisos con COMMIT en 82 ms. El paciente confirmó que el examen se guardó y que el formulario funcionó. El procesamiento no se solicitó: lo mantengo pendiente hasta indicar expresamente el recorrido de extracción y revisión. (José Aránguiz)

Continúo en fase-7/03-atencion-examen del repositorio de pruebas. Debo completar revisión por atención, derivaciones y segundas opiniones antes del cierre y posterior preparación del traspaso al develop actualizado del repositorio oficial. No modifiqué el oficial ni declaré terminada la fase 7. (José Aránguiz)


## Ajuste del recorrido automatizado tras validación en Windows

Registré 763 pruebas backend aprobadas y análisis Flutter sin incidencias. En Flutter pasaron 139 pruebas y falló el recorrido de asignaciones anteriores porque intentaba pulsar Ver exámenes fuera del área visible, desplazado por la tarjeta de atenciones. Añadí ensureVisible y pumpAndSettle antes del tap; conservé las expectativas de apertura del historial y regreso al listado. No oculté advertencias ni modifiqué el comportamiento de la aplicación. La repetición del archivo y de la suite Flutter sigue pendiente en Windows; no doy todavía las 140 pruebas por aprobadas. (José Aránguiz)

## Confirmación local completada

Registré análisis Flutter sin incidencias y las 140 pruebas aprobadas con código 0 tras ajustar el desplazamiento del recorrido anterior. Tras el respaldo, 022 se aplicó con 52 comprobaciones correctas y datos sintéticos revertidos; los permisos finalizaron con COMMIT en 67 ms. El usuario confirmó el recorrido de bandeja, contacto, descarga e inicio persistente. El procesamiento no se solicitó y permanece pendiente hasta indicar el recorrido integrado de revisión. (José Aránguiz)
