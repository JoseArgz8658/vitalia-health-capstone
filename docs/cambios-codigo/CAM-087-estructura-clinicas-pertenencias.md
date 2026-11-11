# CAM-087 — Estructura de clínicas, sucursales y pertenencias

Preparé el primer incremento de la fase 7.2 en fase-7/02-clinicas-pertenencias, desde e2c1964 de la fase 7.1. Añadí seis tablas mediante 013_clinics_memberships, su ejecutor y 28 comprobaciones con datos sintéticos revertidos. No modifiqué migraciones 001..012, datos existentes, dependencias, frontend ni el repositorio oficial. (José Aránguiz)

## Modelo y compatibilidad

Añadí clínicas, sucursales, especialidades, especialidades profesionales, pertenencias a clínicas y pertenencias a sucursales. Cada sucursal referencia una comuna existente. Calle y número son obligatorios; el número es texto para admitir S/N u otros formatos comprobados. Piso, unidad y teléfono son opcionales. La región y provincia se derivan de la comuna. No cargué instituciones, especialidades ni médicos ficticios como datos permanentes. (José Aránguiz)

Las claves foráneas compuestas de branch_memberships obligan a que sucursal y pertenencia correspondan a la misma clínica. Las restricciones UNIQUE evitan duplicar una pertenencia clínica/profesional y una especialidad profesional. Los borrados conservan las restricciones referenciales; no uso CASCADE. Las especialidades rechazan nombres duplicados sin distinguir mayúsculas/minúsculas. (José Aránguiz)

Las pertenencias nacen inactivas y con clinical_role profesional. El campo admite representar jefe_clinico en la futura activación autorizada, pero esta migración no verifica por sí sola una autorización institucional ni la concede. No añadí ese rol a vitalia_roles, no cambié las sesiones ni doy acceso a exámenes por crear una fila. Los estados de clínica, sucursal y pertenencia deben comprobarse en los servicios futuros. Las claves foráneas no sustituyen esas comprobaciones ni implementan por sí solas aislamiento clínico completo. (José Aránguiz)

## Permisos y operación

No concedí a vitalia_app acceso a las seis tablas nuevas. La API y las asignaciones actuales siguen con su contrato anterior; no habilité CRUD institucional ni una pantalla para nombrar jefes clínicos. El siguiente incremento debe implementar autorización, trazabilidad y controles de alcance antes de conceder permisos de aplicación. Las invitaciones conservarán la autorización institucional previa acordada. (José Aránguiz)

El ejecutor específico exige vitalia_dev y la migración 012. applyAdditionalMigration conserva transacción, bloqueo, huella y reversión. Repetir el mismo SQL aplicado informa que ya existía; una huella distinta se rechaza. migrate-all descubre automáticamente 013, por lo que arrancar Compose en esta rama puede ejecutar el cambio: debe revisarse y respaldarse antes. (José Aránguiz)

## Validación

Compilé TypeScript y ejecuté la suite de backend: 45 suites y 504 pruebas aprobadas, salida 0. Añadí cinco casos para requisito de versión, fallos de preparación, inicio de transacción y reversión sin registrar una migración fallida. Después de ajustar una comprobación que podía tropezar antes con la unicidad que con la FK, repetí los cinco casos del bloque y el verificador real aislado. (José Aránguiz)

En PGlite aislado ejecuté 001..012, preparé el historial y apliqué 013. Comprobé aplicación, repetición y rechazo de huella alterada. El verificador aprobó 28 comprobaciones, incluidas relaciones entre clínicas distintas, cambios de clínica incompatibles, duplicados, especialidades, campos opcionales, restricciones de borrado y ausencia de cambios en rol global o verificación profesional. Confirmé que ROLLBACK dejó cero clínicas sintéticas y que un rol vitalia_app sin concesiones no podía leer las seis tablas. El bloqueo advisory se simuló en ese motor: no equivale a PostgreSQL 16 ni a concurrencia real. No incorporé PGlite al proyecto. (José Aránguiz)

## Pendientes

Quedan pendientes validación de esta rama en Windows, respaldo y aplicación deliberada de 013 en PostgreSQL 16, sus 28 comprobaciones y repetición controlada de la migración. No solicito Flutter por este bloque porque no cambié el cliente. No considero terminada la fase 7.2 por añadir estructura: faltan servicios y pantallas institucionales con autorización, y después el flujo de invitaciones. Los pendientes de auditoría/rectificación de perfil y las mejoras de IA conservan su seguimiento. (José Aránguiz)

## Comprobación posterior en Windows y PostgreSQL 16

Ejecuté npm test en Windows: 45 suites y 504 pruebas aprobadas, código de salida 0. Antes de aplicar 013 preparé un respaldo actualizado mediante pgAdmin y confirmé su finalización correcta. Apliqué la migración en vitalia_dev con credenciales administrativas temporales; informó Migración de clínicas y pertenencias aplicada. Ejecuté el verificador: Clínicas y pertenencias: 28 comprobaciones correctas. Datos sintéticos revertidos, código 0. (José Aránguiz)

Esta evidencia comprueba la aplicación y los casos del verificador en PostgreSQL local. La repetición deliberada de 013 y el inventario final quedan por confirmar. No habilité gestión institucional, invitaciones ni acceso clínico; tampoco concedí nuevos permisos a vitalia_app ni cambié el repositorio oficial. La fase 7.2 continúa con sus servicios y pantallas pendientes. (José Aránguiz)

## Inventario confirmado

Comprobé en Query Tool la base vitalia_dev con 31 tablas, 13 migraciones y migracion_013_aplicada=true. El siguiente incremento funcional se registra en CAM-088 y requiere una migración nueva de auditoría; no modifica la 013 aplicada. La repetición deliberada de 013 no fue comunicada y no se declara realizada. (José Aránguiz)
