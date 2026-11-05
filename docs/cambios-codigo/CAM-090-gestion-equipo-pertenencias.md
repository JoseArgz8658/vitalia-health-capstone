# CAM-090 — Listado y gestión auditada del equipo

## Resultado y permisos

Implementé listado paginado, edición de sucursales/especialidades y suspensión/reactivación de pertenencias en `fase-7/02-clinicas-pertenencias`, exclusivamente en el repositorio de pruebas. El jefe activo puede gestionar profesionales ordinarios de su clínica. El administrador consulta el listado y el historial, pero no escribe; tampoco permito que un jefe cambie su propia pertenencia o la de otra jefatura. No incorporé cambio de rol clínico desde el formulario. (José Aránguiz)

El listado muestra nombre, apellido, correo, función institucional, estado, sucursales y especialidades de la clínica. No muestra RUT, fecha de nacimiento, credenciales, documentos ni datos de pacientes. Compruebo sesión, rol, jefatura activa y alcance institucional en el servidor, incluso si se manipula la interfaz. El listado usa páginas de hasta veinte registros y desplazamiento máximo de diez mil. (José Aránguiz)

La suspensión afecta solamente la pertenencia seleccionada. Conservé la cuenta, contraseña, revisiones y pertenencias de otras instituciones. El acceso a exámenes del flujo actual sigue regido por las asignaciones anteriores; este incremento no las revoca ni las convierte en atenciones por clínica. Lo explicité en la pantalla para no presentar esta operación como una suspensión global de acceso clínico. La transición al acceso por examen y clínica sigue pendiente. (José Aránguiz)

## Especialidades y migración 016

Añadí `revision` a las pertenencias y dos tablas: `vitalia_membership_specialties` y `vitalia_membership_audit`. La migración es `016_membership_management` y requiere 015. Desde las 37 tablas posteriores a 015, se esperan 39 tablas y 16 migraciones. No modifiqué 001..015 ni creé múltiples roles globales. Las reservas propuestas de roles y atención pasan a 017 y 018 respectivamente; no eran migraciones ejecutadas. (José Aránguiz)

Separé las especialidades por pertenencia porque la relación anterior `vitalia_professional_specialties` es global a la persona: editarla desde una clínica habría afectado a otras. Conservo esa relación anterior. La migración recupera únicamente especialidades con procedencia explícita en invitaciones activadas de la misma cuenta y clínica. No copio todas las especialidades personales a todas las instituciones ni atribuyo clínica a exámenes históricos. Una pertenencia manual sin esa procedencia puede aparecer sin especialidades institucionales hasta que su jefe las configure. (José Aránguiz)

Adapté las activaciones posteriores a 016 para registrar también sus especialidades institucionales. Las selecciones de sucursal permanecen limitadas a la clínica. Permito conservar relaciones existentes con un elemento del catálogo posteriormente inactivado; no permiten agregar otros elementos inactivos. Así una suspensión no queda impedida por conservar una relación anterior. El formulario incluye las selecciones actuales aunque no estén entre las doscientas opciones activas de catálogo disponibles. (José Aránguiz)

## Auditoría, conflictos y reintentos

Guardo motivo de cinco a quinientos caracteres, cuenta que realizó el cambio, fecha, institución, pertenencia y estados anterior/posterior. Los estados contienen actividad, versión e identificadores de sucursales/especialidades; no incluyen contraseñas ni resultados médicos. El historial identifica al autor por su correo y muestra el motivo y las selecciones. El administrador o jefe autorizado de esa clínica puede consultar hasta veinte cambios por página; la pantalla muestra los veinte más recientes. Los nombres del catálogo se resuelven con las opciones actuales y, si ya no están disponibles, lo indico sin inventar una denominación histórica. (José Aránguiz)

La modificación y la auditoría comparten transacción. Un fallo de inserción en auditoría revierte actividad, relaciones y versión. Añadí un trigger que rechaza UPDATE/DELETE de esta auditoría y permisos de aplicación sin esas operaciones. Los permisos de actualización de pertenencias se restringen a actividad, versión y fecha; no concedí modificación de rol, persona o clínica. Las eliminaciones autorizadas se limitan a las relaciones de sucursal/especialidad reemplazadas dentro de una pertenencia, no a cuentas, pertenencias o revisiones. (José Aránguiz)

Uso el bloqueo institucional compartido con invitaciones y una comprobación de versión bajo bloqueo de fila. Un formulario antiguo devuelve conflicto. El identificador de solicitud y una huella del contenido permiten comprobar un reintento coincidente sin repetir actualización o auditoría; si se reutiliza con otro contenido, actor o alcance, lo rechazo. La pantalla conserva ese identificador tras un fallo y lo renueva cuando se edita el formulario. Guardar sin cambios no escribe; Cancelar no envía modificaciones. (José Aránguiz)

## Archivos principales

| Área | Archivos |
|---|---|
| Estructura y permisos | `backend/database/migrations/016_membership_management.sql`, `backend/database/permissions/team-app.sql` |
| Servicio y API | `backend/src/team/service.ts`, `router.ts`; integración opcional en `app.ts` y `server.ts` |
| Activación compatible | `backend/src/onboarding/service.ts` |
| Ejecución y verificación | `migrate-membership-management.ts`, `verify-team.ts`, `team-verification.ts` en `backend/src/database/` |
| Interfaz | `apps/vitalia/lib/features/equipo/equipo_page.dart`, enlace desde `incorporacion_page.dart`, transporte en `core/auth_api.dart` |
| Pruebas | `backend/test/team.test.cjs`, `apps/vitalia/test/equipo_test.dart` |

## Comprobaciones y límites

Añadí 33 pruebas backend sobre contratos, roles, alcance, versión, auditoría, reintentos y paginación. Ejecuté la suite completa: **599 pruebas aprobadas en 48 suites**, salida 0, en 74,044 segundos. Preparé ocho pruebas Flutter sobre consulta, edición/cancelación, motivo, suspensión, reintento, historial, sesión y transporte. Revisé sintaxis Dart; Flutter no está instalado en el entorno de preparación, por lo que análisis, tests y recorrido en Windows siguen pendientes. (José Aránguiz)

Ejecuté 37 comprobaciones del equipo y las 41 del verificador de invitaciones con datos sintéticos revertidos en un motor PostgreSQL aislado. Además comprobé migración, procedencia de la carga inicial, repetición sin cambios, rechazo de checksum distinto, funcionamiento con rol limitado, activación compatible y reversión cuando falta permiso de insertar auditoría. Simulé el bloqueo advisory y adapté el transporte para ejecutar el DDL; no equivale a validar concurrencia real, PostgreSQL 16 del equipo o Docker. No añadí ese motor como dependencia. (José Aránguiz)

No apliqué 016 ni los nuevos permisos a la base del equipo. La guía es [gestion-equipo.md](../fase-7/gestion-equipo.md). Conservo pendientes suspensión/cambio de jefaturas mediante su procedimiento institucional, acreditación profesional, incorporación de cuentas existentes, edición institucional general y atención por examen. La fase 7.2 y el proyecto completo no se consideran cerrados por este incremento. El repositorio oficial permanece sin cambios. (José Aránguiz)

## Comprobación posterior en Windows

Ejecuté `npm test`: 599 pruebas aprobadas en 48 suites, en 36,122 segundos, con salida 0. Ejecuté `flutter analyze` sin incidencias y `flutter test`: 104 pruebas aprobadas, con salida 0. Estas comprobaciones validan el código; no aplican 016 ni sus permisos a PostgreSQL. El respaldo actualizado, aplicación y verificación en PostgreSQL 16 y recorrido manual del equipo permanecen pendientes. (José Aránguiz)

## Aplicación y recorrido confirmados en PostgreSQL 16 y Windows

Guardé el respaldo previo a 016 y apliqué la migración de gestión de pertenencias en PostgreSQL local. El verificador aprobó 37 comprobaciones y revirtió los datos sintéticos. Ejecuté `team-app.sql` en pgAdmin sobre la base de trabajo y terminó con COMMIT sin errores en 56 ms. (José Aránguiz)

Comprobé el listado del equipo, cancelación sin guardar, validación del motivo obligatorio, suspensión persistente, historial con autor/fecha/motivo/estados y reactivación conservando ambos cambios. Confirmé que la pertenencia del jefe no ofrece edición y que el administrador consulta sin editar. Estos recorridos funcionaron según lo previsto. La suspensión sigue limitada a la pertenencia; no declaro revocadas las asignaciones del flujo anterior. (José Aránguiz)

Conservo pendientes de comprobación manual el conflicto entre dos formularios abiertos y la activación de una nueva invitación con especialidad después de 016. La cobertura automatizada y aislada de esos comportamientos no equivale a haber ejecutado esos recorridos manuales en Windows. Concurrencia real entre instancias, Docker y los demás pendientes de alcance siguen abiertos. El repositorio oficial permanece sin cambios. (José Aránguiz)

## Confirmación de recorridos manuales restantes

Creé una especialidad de prueba desde el administrador, invité y activé un profesional seleccionándola y confirmé su aparición en el equipo institucional. También comprobé el conflicto entre dos formularios: el segundo guardado fue rechazado y conservó el primer cambio. Ambos recorridos funcionaron. Con estas confirmaciones completo los recorridos manuales previstos de CAM-090; no equivalen a pruebas de carga o concurrencia entre varias instancias. (José Aránguiz)

Mantengo pendientes Docker, gestión de jefaturas, acreditación e incorporación de cuentas existentes. Para esta última debe distinguirse la cuenta profesional ya existente de una cuenta de paciente: el modelo actual conserva un único rol global y no debe sustituirlo silenciosamente para aceptar una invitación. El repositorio oficial permanece sin cambios. (José Aránguiz)
