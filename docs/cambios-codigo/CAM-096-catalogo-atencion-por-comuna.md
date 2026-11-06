# CAM-096 — Catálogo de atención por comuna

## Propósito y alcance

Preparé el catálogo que utilizará el paciente al elegir atención para un examen. Busco opciones en la comuna que el paciente confirme, con filtros de clínica, sucursal y especialidad. No interpreto la comuna del perfil como una elección definitiva ni publico una selección clínica automática. Este incremento corresponde al servicio de consulta; todavía no conecté el formulario de carga ni guardé una elección por documento. (José Aránguiz)

## Implementación

Añadí `GET /api/care/catalog` para sesiones activas de paciente. Exijo `communeCode` de cinco dígitos y existencia en el catálogo territorial; admito filtros UUID `clinicId`, `branchId`, `specialtyId` y `offset` entero. Rechazo campos adicionales, listas y filtros inválidos. Utilizo parámetros SQL y una sola sentencia para conservar la misma instantánea de datos. Entrego 30 opciones por página y `nextOffset` explícito. Ordeno por nombres e identificadores para desempatar. La paginación corresponde al catálogo actual, no a una reserva de disponibilidad. (José Aránguiz)

Exijo clínica, sucursal, pertenencia y especialidad activas, relación explícita del profesional con esa sucursal y especialidad de esa clínica, concesión profesional activa y verificación documentada coherente con el perfil global. Una credencial incompleta se excluye sin provocar el fallo de toda la búsqueda. Devuelvo nombre profesional, identificadores de selección y nombre/dirección institucional. No devuelvo teléfono, correo, domicilio personal, RUT, evidencia de credenciales ni datos de exámenes. La respuesta es `no-store`. (José Aránguiz)

No concedí acceso clínico por consultar el catálogo. No modifiqué asignaciones, documentos, sesiones ni permisos de base de datos. Aproveché las lecturas concedidas en los incrementos institucionales y de credenciales. No creé una migración 021, no añadí dependencias del proyecto y no modifiqué el repositorio oficial. (José Aránguiz)

## Comprobaciones

Comprobé la compilación TypeScript y 706 pruebas en 54 suites backend. Las 30 pruebas nuevas cubren sesión/rol, filtros, paginación, errores de esquema/permisos y reversión del verificador. Ejecuté además 28 comprobaciones de SQL con datos sintéticos en PGlite y repetí las 28 con un rol de solo lectura durante la consulta: filtros territoriales, sucursales, especialidades, credenciales alteradas/rechazadas, roles suspendidos, relaciones eliminadas y dos páginas sin duplicados. Los datos sintéticos se revirtieron. El motor aislado sustituye la función de bloqueo advisory para los servicios de preparación; no representa concurrencia real de PostgreSQL 16. (José Aránguiz)

Preparé `verify-care-catalog` para la comprobación nativa. Su ejecución en Windows/PostgreSQL 16 está pendiente, al igual que las pruebas del backend actualizado en el equipo local. No cambié Flutter ni afirmo que el paciente ya pueda utilizar la selección en pantalla. (José Aránguiz)

## Evidencia recibida de CAM-095

Registré las salidas compartidas: 676 pruebas backend en 53 suites, análisis Flutter sin incidencias y 122 pruebas Flutter; migración 020 aplicada; 46 comprobaciones de credenciales y 54 de atención correctas con datos sintéticos revertidos. Los permisos finalizaron con COMMIT en 87 ms. Confirmé mediante el recorrido informado que el perfil profesional aparece verificado. Esta evidencia confirma el recorrido de aprobación informado, no otros recorridos manuales que no hayan sido comunicados. (José Aránguiz)

## Próximos incrementos acordados

Mantengo pendiente dirección y contacto obligatorios al completar el envío, precarga del perfil sujeta a confirmación, zona de consulta distinta del domicilio sin sobrescritura implícita, selección por sucursal/especialidad/profesional, resumen y formulario por pasos dentro de la misma pantalla. La persistencia por examen debe revalidar la elegibilidad al enviar: consultar el catálogo no garantiza que el profesional continúe habilitado. Medicina general se ofrecerá si existe y está habilitada; no crearé una especialidad o profesionales ficticios por inferencia. (José Aránguiz)

Dejé fuera del MVP la comprobación semántica de que el archivo es un examen médico, hasta nueva instrucción. Conservo las validaciones técnicas actuales. Registré para mejoras de interfaz navegación adaptable, acciones agrupadas, formularios por pasos y modernización de Seguridad de acceso, sin afirmar que este incremento las implementa. (José Aránguiz)

Acordé finalizar la fase 7 en el repositorio de pruebas y después comparar con el `develop` actualizado del oficial, preparar y validar la integración antes de fusionar según las reglas del proyecto. Desde esa integración continuaré únicamente en el oficial; conservaré el repositorio de pruebas como historial. No realizaré un traspaso anticipado. (José Aránguiz)

## Confirmación local recibida

Registré 706 pruebas aprobadas en 54 suites en Windows, con código 0. El verificador nativo del catálogo completó sus 28 comprobaciones y revirtió los datos sintéticos. Esta confirmación corresponde al catálogo; no implica validación local de la carga añadida después en CAM-097. (José Aránguiz)
