# CAM-099 — Revisión aprobada por atención

## Alcance

Conecté la extracción existente con la revisión del responsable por examen. La atención debe estar iniciada y tener una extracción requires_review válida. Conservo el resultado original de procesamiento, registro la copia cotejada en vitalia_care_reviews y completo la atención en la misma transacción. No habilito diagnósticos, tratamientos ni aprobaciones automáticas. No cambio el procedimiento de solicitud de procesamiento del paciente. (José Aránguiz)

Reutilicé la política de validación documental del flujo anterior: fechas de calendario, al menos un resultado, conservación del informe ampliado cuando existe, confirmación expresa del cotejo y observaciones obligatorias ante correcciones o datos ausentes. Un campo vacío se guarda como ausente, no como cero. El servidor rechaza identidad de paciente/profesional, campos no previstos, procesamiento ajeno y versiones obsoletas. (José Aránguiz)

El formulario nuevo utiliza tres pasos dentro del detalle de atención: datos del informe, resultados de uno en uno y confirmación. Conservo los controladores al avanzar/retroceder. Permito consultar el texto original y mantengo disponible la descarga del documento. El flujo anterior conserva su presentación y sus rutas; ambos comparten la política de validación. Actualizar revisión solo consulta, no solicita procesamiento ni invoca modelos. (José Aránguiz)

## Integridad y compatibilidad

Añadí 023_care_review_registry con una tabla de referencias comunes y una vista de revisión aprobada vigente. La base tendrá 49 tablas base y una vista de esta integración, con 23 migraciones. Vinculo la referencia a la revisión y al mismo documento/paciente mediante claves compuestas; no creo asignaciones ficticias ni copio resultados entre tablas de revisión. Recupero referencias de revisiones anteriores conservando sus identificadores y snapshots de explicaciones/hilos existentes. (José Aránguiz)

La vista publica revisiones antiguas aprobadas y revisiones por atención aprobadas cuyo estado sea completed. Selecciona la vigente por fecha e identificador, sin borrar las anteriores. Cambié las claves de explicación, auditoría de explicación e hilos del asistente para que referencien el registro común. El paciente, las explicaciones y el chat consultan esa vista; así la revisión nueva no queda desconectada ni se usa una salida preliminar como aprobación. La revisión original sigue inmutable y la IA educativa mantiene approved=false. (José Aránguiz)

En la aprobación bloqueo atención, elegibilidad y procesamiento. La función acotada de bloqueo de procesamiento tiene SECURITY DEFINER, search_path fijo, referencias calificadas y ejecución revocada a PUBLIC; no concede a la API edición de resultados de procesamiento. Inserción de revisión, referencia, auditoría y cierre se confirman juntos o se revierten juntos. Un reintento idéntico con la revisión esperada anterior devuelve la misma aprobación, sin duplicarla; un cambio de contenido o de versión requiere actualizar. (José Aránguiz)

Incluí las atenciones completadas en la bandeja autorizada para consultar su revisión. Continúo exigiendo pertenencia y credencial habilitadas para el acceso profesional. Una suspensión impide nuevas lecturas del profesional, pero no elimina la revisión ya entregada al paciente. Registré las consultas de revisión como view_review en la auditoría de accesos. No concedí UPDATE/DELETE de revisiones o referencias comunes. (José Aránguiz)

## Verificación

Comprobé TypeScript y 789 pruebas backend en 57 suites, incluidas 26 pruebas nuevas. Adapté dos simulaciones de SQL para consultar la vista común y conservé las expectativas de privacidad y estado de procesamiento. Ejecuté 52 condiciones SQL aisladas, repetidas con permisos de aplicación: correcciones y ausencias, rechazo de fechas/identidad/revisión obsoleta, cierre atómico, rollback de revisión/referencia/cierre ante fallo, original intacto, reintento sin duplicación, lectura del paciente y compatibilidad de explicación/chat y de revisiones históricas. No invoqué modelos ni S3 real durante estas comprobaciones. (José Aránguiz)

Comprobé aplicación, repetición, checksum y rollback de 023; probé además recuperación de una revisión antigua con explicación e hilo existentes antes de aplicar la migración. El motor PGlite sustituye advisory locks y no representa concurrencia real entre conexiones PostgreSQL 16. Preparé nueve pruebas Flutter nuevas, adapté la simulación de la bandeja y comprobé sintaxis/formato Dart. Las 149 pruebas esperadas y flutter analyze todavía deben ejecutarse en Windows, junto con respaldo, migración, permisos y recorrido. (José Aránguiz)

## Evidencia anterior y pendientes

Registré CAM-098 con 763 pruebas backend, análisis Flutter sin incidencias y 140 pruebas aprobadas tras corregir el desplazamiento de Ver exámenes. Después del respaldo, 022 se aplicó con 52 comprobaciones revertidas y permisos con COMMIT en 67 ms. El recorrido de bandeja, contacto, descarga e inicio persistente fue confirmado. El usuario no solicitó procesamiento; debo indicar ese recorrido solo después de aplicar y validar este incremento. (José Aránguiz)

Mantengo pendientes derivaciones, segundas opiniones y los demás puntos de cierre de fase 7, incluida su documentación y pruebas integradas. El traspaso al oficial requiere finalizar la fase y comparar con su develop actualizado. No modifiqué el repositorio oficial. (José Aránguiz)

## Confirmación nativa y recorrido recibidos

Registré 789 pruebas backend y 149 Flutter aprobadas, análisis sin incidencias y código 0. Tras el respaldo, 023 se aplicó con 52 comprobaciones correctas y datos sintéticos revertidos; los permisos finalizaron con COMMIT en 92 ms. La extracción terminó requires_review con approved:false; el profesional realizó su aprobación y la atención quedó Completada. El paciente confirmó que ve los resultados revisados. La demora inicial se presentó como procesamiento pendiente; no atribuyo una causa técnica definitiva sin diagnóstico adicional. La API y el procesador automático se ejecutan por separado. (José Aránguiz)
