# Fase 7 — Perfiles, clínicas y atención por examen
Rama activa de atención por examen: fase-7/03-atencion-examen, basada en fase-7/02-clinicas-pertenencias, continuando la base validada de fase-7/01-perfiles-ubicacion. La migración 012 está aplicada y comprobada en PostgreSQL 16 local. El perfil y el guardado/recuperación de medidas se comprobaron en Windows; el catálogo territorial y su selección también se comprobaron en Windows/PostgreSQL 16. Los bloques posteriores siguen pendientes. 013 está aplicada en PostgreSQL 16 local y sus 28 comprobaciones aprobaron; 014 de auditoría institucional está aplicada y comprobada en PostgreSQL 16 local; la creación y consulta institucional se validaron en Windows según CAM-088. 015 de invitaciones está aplicada y validada en Windows/PostgreSQL 16 según CAM-089. 016 de gestión de pertenencias está aplicada y validada según CAM-090. 017 de modos de cuenta y aceptación fue aplicada y validada por el usuario según CAM-091. 018 de contraseñas independientes está aplicada y comprobada según la evidencia de CAM-092; el ajuste de acceso obligatorio y cambio desde el perfil se documenta en CAM-093, con pruebas Windows y flujo manual confirmados; queda pendiente modernizar el formulario; 019 de atención está aplicada y validada según CAM-094 (44 tablas, 19 migraciones y 54 comprobaciones). Preparé 020 de credenciales en CAM-095, pendiente de aplicación local.

## Decisiones confirmadas
Teléfono opcional, un médico responsable por examen a la vez, segunda opinión posterior sin sobrescribir revisión, derivaciones dentro de la misma clínica. Propuesta ampliada: 18 tablas nuevas, importadas como modelo visual separado. Las restricciones del diagrama Oracle no son migraciones PostgreSQL.

## Condiciones observadas en el código
applyAdditionalMigration abre transacción, usa bloqueo advisory, exige versión previa y verifica checksum. migrate-all descubre SQL numerados automáticamente. Por eso los borradores se conservan fuera de backend/database/migrations hasta estar listos para ejecución.
009_professional_reviews conserva UNIQUE processing_id y trigger que rechaza UPDATE/DELETE de revisiones. No editar 001..011 ni eliminar ese trigger para adaptar opiniones posteriores.

## Orden de implementación propuesto
| Bloque | Migración y estado | Entidades | Dependencia y compatibilidad |
|---|---|---|---|
| 1 | 012_profiles_locations | regions, provinces, communes, people, identifiers, patient_profiles, professional_profiles, patient_measurements | Crear primero territorios vacíos para FK de people. No cargar nombres/RUT a partir de exámenes. Perfil ausente sigue permitiendo login actual. |
| 2 | 013_clinics_memberships (aplicada; 28 comprobaciones correctas) | clinics, branches, specialties, professional_specialties, clinic_memberships, branch_memberships | FK compuestas para coherencia de clínica y sucursal. No asignar una clínica ficticia a todos los documentos antiguos. |
| 3 | 017_account_modes (aplicada y validada) | account_roles y active_role en sessions | Copiar concesiones actuales y conservar el modo en cada sesión. Mantener role_code legado y comprobar concesión activa. Aceptación autenticada de invitaciones sin cambiar contraseña. |
| 4 | 019_exam_care_reviews (aplicada y validada) | exam_care, exam_referrals, care_reviews, care_audit | Crear tablas y PK/UNIQUE antes de FK por el ciclo care.prior_review ↔ review.care. Índice parcial de una atención requested/active por documento. Trigger de inmutabilidad para nuevas revisiones. |
| 5 | transición explícita, versión por definir | Puente legado/revisión nueva si es necesario | Definir lectura dual del API, explicación y chat. No aplicar INSERT SELECT que invente sede/profesional responsable. No duplicar una aprobación cambiando su autor. |

Las migraciones concretas dependerán de permisos y consistencia del estado real. Separar DDL listo de borrador; no reservar números mediante SQL incompleto en el directorio autodescubierto.

## Contratos para no romper lo existente
- Login, carga, worker, revisión y chat actuales continúan funcionando mientras no se cambia su contrato.
- accounts.id sigue siendo UUID. La credencial original se conserva en accounts y la profesional independiente en account_roles desde 018.
- El primer bloque no convierte role_code en múltiples roles activos ni cambia /me.
- Perfil incompleto debe mostrarse explícitamente; no bloquear de inmediato cuentas antiguas.
- No tomar nombres/RUT de documentos como identidad verificada de la cuenta.
- La clínica del informe transcrito no es automáticamente el tenant de atención.
- La revisión nueva pertenece a una atención y se guarda en care_reviews. professional_reviews sigue como legado inmutable. El UNIQUE actual se conserva.
- El asistente debe utilizar una revisión seleccionada/autorizada, no mezclar opiniones ni datos de otros documentos.
- Obtener cita de segunda opinión no permite al médico leer todos los exámenes del paciente.
- Derivación transaccional cambia responsabilidad autorizada y registra trazabilidad. Acceso a revisión ya aprobada sigue una política explícita.
- El jefe clínico opera solo en su clínica. Administrador técnico no recibe acceso clínico por gestionar infraestructura.

## Verificación antes de aplicar
Ejecutar preflight-fase-7.sql en Query Tool sobre vitalia_dev. Es solo lectura y devuelve versiones, resumen de registros y coincidencias de nombres nuevos. No envía datos a IA. Revisar el estado antes de escribir la primera migración.
Un respaldo debe incluir PostgreSQL y referencia a originales en S3. No usar DROP TABLE como estrategia para revertir una migración con perfiles nuevos.

## Pruebas por bloque
1. Migración: versión previa, ejecución repetida sin cambios, checksum cambiado rechazado, fallo con rollback, migración sobre esquema previo y esquema nuevo.
2. Perfiles: cuenta sin perfil, persona única por cuenta, teléfono nulo, segundo apellido opcional, identificador duplicado, medición positiva/unidad/fecha, permisos de edición propios.
3. Clínicas: pertenencia activa y revocada, sede de otra clínica, roles de jefe clínico y administrador técnico.
4. Roles: sesión vieja y nueva, usuario con ambos perfiles, elección de rol activo sin confiar en solicitud manipulada.
5. Atención: dos solicitudes concurrentes no crean dos responsables; segunda opinión conserva previa; profesional ajeno no lee documento; derivación entre tenants rechazada.
6. Revisiones: autoría, copia original conservada, inmutabilidad, compatibilidad de chat/explicaciones y selección de revisión.
Después de cambios reales en Flutter: analyze y tests pertinentes. No pedir pruebas Flutter por archivos de planificación.

## Antes de completar registro
Queda por definir política de personas sin RUT, verificación profesional/identidad y creación inicial de jefes clínicos. En el primer bloque se puede crear estructura sin marcar identidades verificadas ni imponer requisitos que aún no se han acordado.

## Pendientes conservados
Fase 6: ordenar modelo propuesto, vistas por área cuando haya tiempo, iconos Android y accesibilidad. IA: cobertura/rendimiento en docs/pendientes. Seguridad PostgreSQL: usuario limitado/coordinación con compañero; debe resolverse antes de despliegue. Estos trabajos no se declaran cerrados por iniciar fase 7.

## Avance 7.1 — 15 de octubre de 2026

Preparé ocho tablas nuevas mediante 012_profiles_locations, sin modificar 001..011 ni los roles actuales. Añadí el ejecutor específico, 33 comprobaciones con datos sintéticos revertidos, pruebas de manejo de fallos y la guía [bloque-1-perfiles-ubicacion.md](bloque-1-perfiles-ubicacion.md). Este incremento es la base de datos: las rutas y pantallas para completar perfil siguen pendientes. Antes de habilitar captura de RUT faltan normalización y módulo 11. (José Aránguiz)

Acordé para los siguientes bloques: el administrador invita al primer jefe clínico solo con autorización institucional previa verificada; el jefe invita profesionales únicamente de su clínica. El paciente elige al profesional por examen y puede consultar extracción/chat preliminar con advertencia y fuente diferenciada. Estos cambios todavía no están implementados. No añado un rol de director dentro de la aplicación. (José Aránguiz)

## Continuación funcional 7.1 — CAM-083

Añadí la API de perfil propio y la pantalla Mi perfil, con RUT opcional normalizado y validado por módulo 11. Separé los permisos de edición por columnas de la migración; su concesión en vitalia_dev requiere ejecución administrativa deliberada. Incorporé la validación de 33 comprobaciones en PostgreSQL 16 y 428 pruebas Windows en CAM-082. La continuación aprobó 456 pruebas backend; Flutter y flujo real del perfil quedan pendientes en Windows. Medidas, catálogo de comunas e invitaciones clínicas siguen pendientes. (José Aránguiz)

## Medidas y estado posterior — CAM-084 / CAM-085

Comprobé el perfil propio en Windows y el ajuste de consulta/edición por secciones con 80 pruebas Flutter y análisis sin incidencias. Añadí el módulo opcional de peso/altura con historial propio y fuente patient_reported. El backend del nuevo módulo aprobó 482 pruebas; Flutter y flujo real de medidas siguen pendientes en Windows. No cambié 012 ni cargué catálogo territorial. Las clínicas e invitaciones siguen en los siguientes bloques. (José Aránguiz)

## Comprobación Windows de medidas — 29 de octubre de 2026

Comprobé 82 pruebas Flutter, análisis sin incidencias y 482 pruebas backend en 43 suites, con salida 0. Apliqué los permisos de perfiles/medidas en vitalia_dev y confirmé guardado y recuperación de las medidas al reabrir Mi perfil. La evidencia está en [CAM-085](../cambios-codigo/CAM-085-medidas-personales.md). No declaro comprobados manualmente los recorridos no informados. (José Aránguiz)

Preparé el catálogo versionado de SUBDERE y la selección de comuna dependiente de región/provincia en CAM-086. Su ejecución en Windows y carga en PostgreSQL 16 siguen pendientes. También quedan por definir la auditoría específica y la rectificación de medidas. Las clínicas, pertenencias, invitaciones y atención por examen conservan su estado de propuesta; no se integran al repositorio oficial por esta comprobación. (José Aránguiz)

## Catálogo territorial — CAM-086

Añadí la carga administrativa explícita del catálogo SUBDERE-CUT-2018-v04 y la selección opcional en Contacto, sin modificar 012 ni crear 013. El backend aprobó 499 pruebas en 44 suites; la verificación aislada de catálogo/perfil aprobó 14 condiciones. Flutter y PostgreSQL 16 de este incremento quedan pendientes. La guía está en [bloque-1-perfiles-ubicacion.md](bloque-1-perfiles-ubicacion.md). (José Aránguiz)


## Cierre funcional de ubicación y siguiente bloque — 29 de octubre de 2026

Comprobé el incremento de ubicación de CAM-086 en Windows y PostgreSQL 16: 499 pruebas backend, 86 Flutter, análisis sin incidencias, catálogo cargado, permisos aplicados y todos los recorridos manuales de selección, persistencia, dependencia, cancelación y ubicación opcional funcionales. Los apartados históricos anteriores conservan el estado que tenían al registrarse. (José Aránguiz)

La base funcional 7.1 comprende perfiles, medidas y ubicación. Auditoría específica, rectificación y ampliación de validación en dispositivos permanecen como pendientes explícitos antes del despliegue real. El siguiente bloque propuesto es 7.2: clínicas, sucursales, especialidades y pertenencias. La migración 013 todavía no está creada ni aplicada. Las invitaciones y la designación institucional de jefes clínicos requieren su flujo específico; no deben habilitarse mediante edición directa de un rol. No se asignarán clínicas ficticias a los documentos existentes ni se ampliará el acceso clínico del administrador. (José Aránguiz)

## Inicio de fase 7.2 — CAM-087

Preparé seis tablas institucionales y la migración 013 desde la base validada de 7.1, con ejecutor y 28 comprobaciones revertibles. El backend aprobó 504 pruebas en 45 suites. El motor aislado comprobó migración, repetición, huella, restricciones y ausencia de permisos para la aplicación. La validación en Windows y la aplicación en PostgreSQL 16 están pendientes. La guía es [bloque-2-clinicas-pertenencias.md](bloque-2-clinicas-pertenencias.md). (José Aránguiz)

Las pertenencias son inactivas por defecto y no conceden acceso a exámenes. No modifiqué las migraciones anteriores, Flutter, roles globales, revisiones, asignaciones ni el repositorio oficial. La fase 7.2 sigue abierta: faltan API y pantallas con autorización institucional, trazabilidad y permisos específicos. Las invitaciones del jefe clínico permanecen en su bloque posterior. (José Aránguiz)


## Validación local de la estructura 7.2

Comprobé 504 pruebas backend en Windows, respaldo finalizado y aplicación de 013 en vitalia_dev. El verificador aprobó 28 comprobaciones y revirtió los datos sintéticos, salida 0. La evidencia está en CAM-087. Conservo pendientes inventario final y repetición de la migración; los servicios, pantallas y autorizaciones institucionales de 7.2 todavía no están implementados. No cambió el repositorio oficial. (José Aránguiz)

## Gestión institucional — CAM-088

Registré el inventario confirmado por Query Tool: vitalia_dev, 31 tablas, 13 migraciones y 013 aplicada. Preparé creación y consulta de clínicas/sucursales para administrador, con auditoría atómica y reintentos identificados. Añadí 014_institution_audit y permisos separados; no modifiqué 013. El número 014 reservado para roles era una propuesta sin SQL creado y se desplaza a 015; atención por examen queda propuesta para 016. (José Aránguiz)

El backend aprobó 530 pruebas y el servicio pasó 14 comprobaciones aisladas. Las rutas no otorgan acceso a exámenes ni permiten designar jefes clínicos. Flutter, 014 y permisos de este incremento siguen pendientes en Windows/PostgreSQL 16. La guía está en [gestion-institucional.md](gestion-institucional.md). No se considera terminada la fase 7.2. (José Aránguiz)


## Estado vigente después de validar gestión institucional

Comprobé creación, consulta y persistencia de clínicas y sucursales, cancelación del formulario y restricciones de acceso de paciente/profesional. Registré 530 pruebas backend en 46 suites, 90 pruebas Flutter y análisis sin incidencias, con salida 0. Apliqué 014 y sus permisos; el verificador aprobó 14 comprobaciones y revirtió los datos sintéticos. También confirmé visualmente la ayuda contextual del número de dirección. La evidencia está en [CAM-088](../cambios-codigo/CAM-088-gestion-institucional.md). Las cifras automatizadas corresponden a la versión previa al ajuste de ayuda. Los estados pendientes en apartados anteriores se conservan como registro histórico. (José Aránguiz)

La fase 7.2 sigue abierta: la estructura de especialidades y pertenencias existe, pero su gestión funcional no está habilitada. También permanecen pendientes edición y cambios de estado institucionales con auditoría. No considero activada la atención multiclínica ni la incorporación de profesionales por haber completado la creación de instituciones. (José Aránguiz)

### Siguiente incremento propuesto: incorporación institucional de profesionales

Propongo completar el flujo de pertenencias mediante autorización institucional e invitaciones, antes de habilitar altas profesionales desde la interfaz. Su alcance será el siguiente. (José Aránguiz)

1. Registrar una solicitud externa del representante autorizado, vinculada a una clínica existente, con identidad/cargo del solicitante, referencia verificable de la autorización y fecha. No crear un rol de director dentro de la aplicación.
2. Registrar el administrador que verifica la procedencia y autoridad del solicitante y cuándo lo hace. Impedir una invitación de jefe clínico sin autorización verificada para esa misma clínica.
3. Crear una invitación individual con vencimiento, revocación y uso único; conservar solo la huella del token. El destinatario establece su contraseña al activar su cuenta. No guardar contraseñas en documentación ni registrar tokens en auditoría.
4. Activar la pertenencia de jefe clínico únicamente al completar la invitación y registrar cuándo se activa. Definir expresamente el tratamiento de cuentas profesionales existentes sin cambiar sus credenciales ni roles por coincidencia de correo.
5. Permitir al jefe invitar profesionales exclusivamente a su clínica, dentro de los permisos que puede gestionar. Incorporar especialidades y sucursales de forma coherente con esa pertenencia.
6. Comprobar vencimiento, reintentos, uso concurrente del token, clínica cruzada, ausencia de autorización y límites del jefe clínico. Gestionar instituciones no habilitará lectura de exámenes ni acceso automático a todos los pacientes.

Este incremento todavía no está implementado. Antes de escribir una nueva migración revisaré el orden efectivo de versiones: 015 para roles es una propuesta y no una migración ejecutada. Conservaré las revisiones y el flujo actual durante la transición. La entrega al repositorio oficial seguirá requiriendo comparación previa y autorización explícita. (José Aránguiz)

## Incorporación institucional preparada — CAM-089

Implementé autorización institucional vinculada a clínica y correo designado, verificación administrativa explícita, invitaciones de 48 horas y activación de cuentas nuevas con contraseña propia. El jefe activo invita únicamente profesionales de su clínica. Las selecciones de sucursal/especialidad se conservan en la pertenencia activada; no conceden acceso automático a pacientes. Utilicé el rol global profesional existente, sin activar múltiples roles. La migración 015 añade cinco tablas y requiere 014. La reserva de roles pasa a 016 y atención por examen a 017; eran propuestas sin SQL aplicado. (José Aránguiz)

Comprobé 566 pruebas backend y 41 condiciones de base de datos en motor aislado, además de repetición/checksum, rol limitado y rollback de activación ante fallo de auditoría. Preparé seis pruebas Flutter; su ejecución y recorrido en Windows, aplicación de 015 y permisos en PostgreSQL 16 siguen pendientes. La guía es [invitaciones-institucionales.md](invitaciones-institucionales.md). No considero terminada la fase 7.2 ni modificado el repositorio oficial. La suspensión/edición auditadas, incorporación de cuentas existentes y acreditación profesional conservan su estado pendiente. (José Aránguiz)

## Validación local de incorporación institucional — CAM-089

Comprobé 566 pruebas backend y 96 Flutter, con análisis sin incidencias y salida 0. Guardé respaldo previo, apliqué 015 en PostgreSQL 16, obtuve 41 comprobaciones correctas con datos sintéticos revertidos y ejecuté los permisos específicos con COMMIT sin errores. Confirmé el recorrido de autorización e invitación del primer jefe clínico y la invitación/activación de otro profesional de su clínica. El profesional ordinario no pudo invitar y permaneció sin pacientes ni exámenes asignados. (José Aránguiz)

Quedan pendientes los recorridos manuales de reutilización y revocación del código, concurrencia real y Docker. La fase 7.2 conserva los pendientes de suspensión/edición auditadas, incorporación de cuentas existentes y acreditación profesional. Elección de profesional por examen, derivaciones y vista/chat preliminares no están implementados por esta validación. La evidencia está en CAM-089 y el repositorio oficial permanece sin cambios. (José Aránguiz)

## Gestión auditada del equipo preparada — CAM-090

Confirmé los recorridos manuales restantes de CAM-089: rechazo del código consumido y de la invitación revocada. Preparé el listado del equipo, edición de sucursales/especialidades y suspensión/reactivación auditadas de profesionales ordinarios por el jefe de su clínica. El administrador consulta sin editar y las jefaturas conservan su procedimiento institucional separado. La guía es [gestion-equipo.md](gestion-equipo.md). (José Aránguiz)

Añadí 016 con versión de pertenencia, especialidades por pertenencia y auditoría inmutable. Conservé las especialidades personales globales y recuperé únicamente relaciones con procedencia explícita de invitaciones activadas de esa cuenta y clínica. No modifiqué 015 ni anteriores. Los números propuestos para roles y atención pasan a 017 y 018; todavía no tienen SQL aplicado. (José Aránguiz)

El verificador aislado aprobó 37 condiciones del equipo y conservó las 41 de invitaciones; comprobé rol limitado, repetición/checksum y rollback ante fallo de auditoría. Flutter, esquema/permisos en PostgreSQL 16 y recorridos de este incremento están pendientes en Windows. La suspensión no revoca asignaciones del flujo anterior ni afecta otra institución. La transición a atención por examen, suspensión de jefaturas, incorporación de cuentas existentes y acreditación profesional permanecen pendientes. El repositorio oficial no se modifica. (José Aránguiz)

## Modos y activación independiente — CAM-091

Confirmé dos entregas complementarias: manual y por correo cuando configure ese servicio. Retiré la activación del inicio y preparé su dirección independiente. Añadí selección Paciente/Profesional con Paciente inicial, acceso administrativo separado y sesión ligada al modo autorizado. La aceptación autenticada de invitación incorpora cuentas de paciente/profesional existentes, conserva contraseña/datos y no amplía sesiones anteriores. (José Aránguiz)

Preparé 017 con concesiones por cuenta y modo activo de sesión. Comprobé 617 pruebas backend y 27 condiciones de modos/aceptación en motor aislado, conservando 41 de invitaciones y 37 de equipo. Añadí siete pruebas Flutter, pendientes de ejecución en Windows junto con análisis, migración/permisos y recorrido real. La guía es [modos-acceso.md](modos-acceso.md). La entrega manual está preparada; el envío de correo y dirección pública se configurarán sin eliminarla. (José Aránguiz)

La habilitación voluntaria de Paciente para una cuenta inicialmente solo profesional conserva su pendiente: no concedo todos los perfiles automáticamente. Tampoco considero implementadas atención por examen, acreditación, gestión de jefaturas, Docker o concurrencia real. El repositorio oficial permanece sin cambios. (José Aránguiz)

## Contraseñas independientes — 29 de octubre de 2026

Preparé 018_mode_passwords sin reescribir 017. Separé la credencial profesional adicional de la del paciente, con configuración inicial para cuentas duales previas. Conservé los datos, roles y contraseñas originales. La siguiente atención por examen queda propuesta como 019. Véanse [CAM-092](../cambios-codigo/CAM-092-contrasenas-independientes-por-modo.md) y [guía de ejecución](contrasenas-por-modo.md). La aplicación local sigue pendiente. (José Aránguiz)

## Ajuste de acceso y contraseña desde el perfil

Retiré el botón de configuración del inicio. Preparé configuración obligatoria mediante autorización limitada para cuentas duales antiguas y cambio de contraseña desde Seguridad de acceso en el perfil profesional. Utilicé 018 sin alterar su SQL ni crear otra migración. Véase CAM-093. La siguiente migración de atención por examen permanece propuesta como 019. (José Aránguiz)

## Continuación tras CAM-093

Registré el funcionamiento manual confirmado del acceso y cambio de contraseña, con 117 pruebas Flutter y 646 backend aprobadas en Windows. Dejé pendiente modernizar visualmente el formulario sin cambiar sus validaciones. La salida compartida no confirma las 49 comprobaciones ampliadas en PostgreSQL 16.

El siguiente bloque del plan es atención por examen: elección de clínica, especialidad y profesional por el paciente, responsable único, derivación dentro de la institución y conservación de revisiones anteriores. Debo concretar el criterio de profesionales elegibles y la compatibilidad con asignaciones y revisiones existentes antes de aplicar una migración de atención. La extracción preliminar con advertencia y el envío de invitaciones por correo siguen pendientes independientes. No he iniciado la migración 019 ni modificado el repositorio oficial. (José Aránguiz)

## Inicio autorizado de atención por examen — CAM-094

Preparé 019 con cuatro tablas, integridad por documento/paciente/clínica, responsable único, revisiones inmutables, derivación atómica y auditoría. No migré datos históricos ni concedí acceso de API a las tablas nuevas. La estructura requiere después servicios, permisos por examen y pantallas. El criterio de elegibilidad exige perfil verificado con referencia profesional; no equivale a activar una invitación. Debo implementar su verificación auditable antes de publicar profesionales elegibles. La guía es [atencion-por-examen.md](atencion-por-examen.md). No he aplicado 019 en la base del usuario. (José Aránguiz)

## Verificación profesional — CAM-095

Preparé 020 con solicitud institucional y decisión administrativa auditable sobre la credencial global. El jefe registra antecedentes de su clínica y no decide verificaciones globales; el administrador registra fuente y fundamento sin obtener acceso clínico. Endurecí la elegibilidad para exigir evidencia documentada y conservé las 54 comprobaciones de atención. La aplicación local y Flutter siguen pendientes. La guía es [credenciales-profesionales.md](credenciales-profesionales.md). Después continuaré con catálogo y elección por documento; no doy esa funcionalidad por implementada todavía. (José Aránguiz)

## Validación de credenciales y catálogo territorial de atención — CAM-096

Registré 020 aplicada en PostgreSQL local, 46 comprobaciones de credenciales, 54 de atención y permisos con COMMIT; también el recorrido informado con perfil verificado. Añadí el catálogo de atención por comuna confirmada, con sucursales/especialidades/pertenencias activas y credenciales documentadas. Comprobé 706 pruebas backend y 28 condiciones SQL aisladas, repetidas con rol de lectura durante la consulta. No añadí migración ni cambié Flutter. La comprobación nativa del nuevo catálogo permanece pendiente. Véase [catalogo-atencion.md](catalogo-atencion.md). (José Aránguiz)

Ajusté el próximo flujo: ubicación/contacto obligatorios al envío, datos precargados del perfil con confirmación, zona de atención modificable sin cambiar implícitamente el domicilio, clínica/sucursal/especialidad/profesional, archivo y resumen final en pasos dentro de la misma pantalla. Todavía debo implementar esos formularios y su persistencia/revalidación por examen; no los considero resueltos por el catálogo. La comprobación semántica del archivo como examen queda fuera del MVP hasta nueva instrucción. Las mejoras generales de diseño permanecen planificadas. (José Aránguiz)

Terminaré la fase 7 en el repositorio de pruebas. Antes del traspaso compararé con el `develop` actualizado del oficial y prepararé una integración comprobada para su revisión/fusión según las reglas acordadas. Desde ese momento trabajaré únicamente en el oficial y conservaré el de pruebas como historial. (José Aránguiz)

## Carga con elección y contacto preparados — CAM-097

Registré CAM-096 validado en Windows con 706 pruebas y en PostgreSQL con 28 comprobaciones revertidas. Preparé 021_care_upload, contacto inmutable por examen y cuatro pasos de carga con residencia/zona separadas. El paciente confirma la atención y decide si guardar domicilio/teléfono; el servidor obtiene el correo y revalida credenciales/relaciones al confirmar. Véase [carga-con-atencion.md](carga-con-atencion.md). (José Aránguiz)

Comprobé 734 pruebas backend en 55 suites y 34 condiciones SQL aisladas, repetidas con permisos de aplicación. Preparé nueve pruebas Flutter nuevas y adapté una existente: 131 pruebas esperadas, todavía pendientes en Windows junto con análisis, respaldo, migración/permisos y recorrido. No confundo formateo Dart con ejecución Flutter. (José Aránguiz)

Separé el acceso de los documentos nuevos respecto de las asignaciones históricas. La bandeja clínica por examen y las acciones del responsable, derivaciones, segundas opiniones y lectura de contacto bajo esos permisos todavía requieren su siguiente incremento; no doy la fase por cerrada. Conservé fuera del MVP la comprobación semántica del archivo como examen. El traspaso al oficial permanece condicionado al cierre y a la comparación con develop actualizado. (José Aránguiz)

## Bandeja del responsable preparada — CAM-098

Registré CAM-097 validado: 734 pruebas backend y 131 Flutter, análisis sin incidencias, respaldo, 021 aplicada con 34 comprobaciones revertidas y permisos con COMMIT en 82 ms. El recorrido manual confirmó examen guardado. La extracción no se solicitó y permanece pendiente por acuerdo. (José Aránguiz)

Preparé 022_care_inbox, bandeja paginada del responsable, contacto confirmado, descarga revalidada y comienzo auditado de atención. Comprobé 763 pruebas backend y 52 condiciones SQL aisladas, repetidas con permisos de aplicación, además de repetición/checksum/rollback. Nueve pruebas Flutter nuevas están preparadas; 140 pruebas esperadas pendientes en Windows, junto con migración, permisos y recorrido. Véase [bandeja-por-examen.md](bandeja-por-examen.md). (José Aránguiz)

No habilité extracción ni aprobación por esta bandeja. Debo continuar con revisión por atención, derivaciones y segundas opiniones; mantengo el trabajo en el repositorio de pruebas hasta el cierre, seguido de comparación/preparación de integración con develop oficial. (José Aránguiz)

## Revisión por atención preparada — CAM-099

Registré CAM-098 validado con 763 pruebas backend, análisis Flutter y 140 pruebas correctas, respaldo, 022 aplicada con 52 comprobaciones revertidas, permisos con COMMIT en 67 ms y recorrido manual funcional. La extracción aún no fue solicitada. (José Aránguiz)

Preparé 023_care_review_registry, aprobación inmutable y cierre atómico de atención, formulario por pasos y lectura común para paciente/explicaciones/chat sin fabricar asignaciones ni copiar resultados. Comprobé 789 pruebas backend, 52 condiciones SQL aisladas repetidas con permisos de aplicación y migración/repetición/checksum/rollback, incluida compatibilidad de referencias históricas. Preparé nueve pruebas Flutter: 149 esperadas pendientes en Windows junto con la aplicación del esquema/permisos y el recorrido real. Véase [revision-por-atencion.md](revision-por-atencion.md). (José Aránguiz)

Después de aplicar este incremento indicaré la solicitud de procesamiento y su revisión real. Mantengo pendientes derivaciones, segundas opiniones y cierre integrado de fase 7 antes de comparar y preparar la integración con develop oficial. (José Aránguiz)

## Derivación y seguimiento preparados — CAM-100

Registré CAM-099 aplicado y validado: 789 pruebas backend y 149 Flutter, análisis sin incidencias, respaldo, 023 con 52 comprobaciones revertidas, permisos con COMMIT en 92 ms, extracción requires_review y aprobación humana con estado Completada. El paciente confirmó acceso a los resultados aprobados. (José Aránguiz)

Preparé 024_clinic_referrals, traslado atómico a otro responsable de la misma clínica, motivo visible, reintento sin duplicados y seguimiento del paciente. Comprobé 815 pruebas backend y 49 condiciones SQL aisladas repetidas con permisos de aplicación, junto con migración/repetición/checksum/rollback. Nueve pruebas Flutter nuevas están preparadas: 158 esperadas pendientes en Windows. Véase [derivacion-institucional.md](derivacion-institucional.md). (José Aránguiz)

La derivación opera sobre atenciones abiertas, conserva el historial y no reabre aprobaciones. Debo continuar con la segunda opinión del paciente y el cierre integrado de la fase 7 antes de preparar el traspaso al oficial y su comparación con develop actualizado. (José Aránguiz)
