# CAM-089 — Autorización e invitaciones institucionales

## Resultado y alcance

Implementé la incorporación institucional en `fase-7/02-clinicas-pertenencias`, únicamente en el repositorio de pruebas. Conservé el rol global `profesional`; identifico al jefe clínico mediante su pertenencia activa a una clínica y compruebo esa pertenencia en cada operación. No añadí un rol de director ni cambié contraseñas, roles o asignaciones existentes. (José Aránguiz)

Registré la autorización externa con nombre, cargo y contacto del solicitante, referencia verificable, fecha, cuenta que la registra, correo del jefe designado y clínica. Separé el registro de la verificación: el administrador debe confirmar que comprobó fuera de la aplicación la procedencia y autoridad del solicitante. La aplicación registra esa verificación manual; no acredita por sí misma la autenticidad del documento o de la representación institucional. (José Aránguiz)

El administrador puede invitar al primer jefe solo si la autorización está verificada, no revocada y corresponde a la misma clínica y correo. Rechazo un segundo jefe activo o una invitación de jefe pendiente y vigente en esa clínica. El jefe activo puede invitar únicamente profesionales de su propia institución; no puede invitar jefes ni crear especialidades globales. El administrador incorpora al catálogo denominaciones revisadas por el equipo; el jefe selecciona especialidades existentes y sucursales activas de su clínica. Esa selección no acredita habilitación profesional. (José Aránguiz)

## Activación y límites de permisos

Generé códigos aleatorios de 256 bits, con vencimiento de 48 horas, revocación y uso único. Persisto solamente su huella SHA-256. El código aparece una vez en la pantalla de quien invita, para entregarlo por privado al destinatario. Los listados y la auditoría no devuelven el código ni su huella. No implementé envío de correos ni incluí códigos en enlaces o parámetros de URL. Si se pierde el código, se revoca la invitación y se emite otra. Una invitación vencida pendiente del mismo correo también requiere revocación antes de otra emisión. (José Aránguiz)

La activación pública recibe el código en el cuerpo de POST, primer nombre, primer apellido, contraseña y confirmación. Conservé scrypt y la política de al menos doce caracteres y máximo 1024 bytes. Rechazo un código inválido antes de calcular scrypt y limito a una activación simultánea por proceso de API. Revalido el código, clínica, autorización o jefatura del emisor y las selecciones después del hash, dentro de la transacción. No creo sesión automáticamente; el destinatario vuelve al inicio de sesión. (José Aránguiz)

Creo cuenta profesional, persona, perfil profesional pendiente de verificación, pertenencia activa, relaciones de sucursal/especialidad, consumo del código y auditoría en una transacción. Si falla la auditoría, no informo éxito ni conservo una cuenta parcial. Serializo las operaciones institucionales por clínica y bloqueo la invitación durante su consumo. Las verificaciones de concurrencia real en PostgreSQL 16 y entre varias instancias siguen pendientes. (José Aránguiz)

No incorporé cuentas existentes mediante invitación: si el correo ya está registrado, rechazo el alta sin modificar contraseña, rol ni perfil. También compruebo este caso durante la activación por si la cuenta se registró después de emitir la invitación. La incorporación de una cuenta existente necesita un flujo separado, con autenticación y aceptación explícitas. (José Aránguiz)

Una autorización ya utilizada para activar un jefe no se revoca por esta operación: su historial permanece y la futura suspensión de la pertenencia requerirá un flujo específico auditado. Revocar una invitación tampoco suspende una cuenta activada. La pertenencia institucional no concede acceso automático a pacientes o exámenes y no crea asignaciones del flujo anterior. (José Aránguiz)

## Archivos principales y migración

| Área | Archivos |
|---|---|
| Estructura aditiva | `backend/database/migrations/015_institution_invitations.sql` |
| Aplicación y comprobación | `migrate-invitations.ts`, `verify-invitations.ts`, `invitations-verification.ts` en `backend/src/database/` |
| Permisos deliberados | `backend/database/permissions/invitations-app.sql` |
| Servicio y API | `backend/src/onboarding/service.ts`, `router.ts`, integración opcional en `app.ts` y `server.ts` |
| Interfaz | `features/incorporacion/`, acceso desde login y espacio administrativo/profesional; transporte en `core/auth_api.dart` |
| Pruebas | `backend/test/onboarding.test.cjs`, `apps/vitalia/test/incorporacion_test.dart` |

Añadí cinco tablas: `vitalia_institution_authorizations`, `vitalia_professional_invitations`, `vitalia_invitation_branches`, `vitalia_invitation_specialties` y `vitalia_onboarding_audit`. Desde las 32 tablas posteriores a 014, se esperan 37 tablas y 15 migraciones. No modifiqué 001..014. El número 015 para roles era una propuesta sin SQL ejecutable: queda desplazada a 016 y atención por examen a 017. Este incremento no implementa múltiples roles globales ni cambia `/me`. (José Aránguiz)

Preparé permisos por columnas para las nuevas escrituras y auditoría solo de inserción. No concedí modificación de contraseñas/roles existentes, actualización de pertenencias, borrado ni lectura de la nueva auditoría a la aplicación. El servicio controla la autorización por actor y clínica; estas concesiones SQL no sustituyen esos controles. El script exige `vitalia_dev` y un `vitalia_app` sin privilegios administrativos. No lo ejecuté contra la base del equipo. (José Aránguiz)

## Verificación realizada

Ejecuté la compilación TypeScript y la suite completa: **566 pruebas aprobadas en 47 suites**, salida 0. Añadí 36 casos sobre contratos estrictos, permisos, vinculación al correo/clínica, sesión, privacidad de tokens, rechazo temprano, cupo de activación y fallos de auditoría. Después amplié únicamente el verificador de base de datos y volví a compilarlo. (José Aránguiz)

El verificador aprobó **41 comprobaciones** con datos sintéticos revertidos en un motor PostgreSQL aislado. Comprobé además aplicación/repetición de 015 y rechazo de una huella distinta, activación con un rol limitado, permisos denegados y reversión ante pérdida del permiso de insertar auditoría. Adapté el transporte del motor aislado para ejecutar DDL con varias sentencias y simulé sus bloqueos advisory; no equivale a probar PostgreSQL 16, Docker o concurrencia real. No agregué ese motor como dependencia del proyecto. (José Aránguiz)

Preparé seis pruebas Flutter y comprobé sintaxis con Dart. Flutter no está instalado en este entorno: `flutter analyze`, `flutter test` y recorrido visual quedan pendientes en Windows. Tampoco apliqué 015 ni los permisos en `vitalia_dev`. No considero cerrado el bloque hasta recibir esas comprobaciones. La guía está en [invitaciones-institucionales.md](../fase-7/invitaciones-institucionales.md). (José Aránguiz)

## Pendientes conservados

Conservo pendientes la gestión auditada de suspensión/edición institucional y profesional, incorporación de cuentas existentes, acreditación profesional, administración ampliada del catálogo de especialidades y paginación más allá de los límites iniciales. El selector muestra hasta 200 clínicas, sucursales y especialidades; los historiales recientes, hasta 50 autorizaciones/invitaciones. También siguen pendientes elección de profesional por examen, derivaciones, segunda opinión y vista/chat preliminares para el paciente. No modifiqué el repositorio oficial. (José Aránguiz)

## Comprobación posterior en Windows

Ejecuté `npm test`: 566 pruebas aprobadas en 47 suites, en 35,693 segundos, con salida 0. Ejecuté `flutter analyze` sin incidencias y `flutter test`: 96 pruebas aprobadas, con salida 0. Los avisos de consola de los casos negativos del backend no produjeron fallos en la suite. Estas comprobaciones no aplican 015 ni sus permisos a PostgreSQL. El respaldo actualizado, aplicación y verificación en PostgreSQL 16 y recorrido manual de invitaciones continúan pendientes. (José Aránguiz)

## Aplicación y recorrido confirmados en PostgreSQL 16 y Windows

Guardé el respaldo previo y apliqué 015 en PostgreSQL local. El ejecutor informó «Migración de invitaciones institucionales aplicada» y el verificador aprobó 41 comprobaciones con datos sintéticos revertidos. Ejecuté el archivo de permisos en pgAdmin y finalizó con COMMIT sin errores, en 77 ms. (José Aránguiz)

Comprobé desde la interfaz el registro de autorización, su verificación, emisión de la invitación del primer jefe clínico, activación y acceso a su clínica. Después comprobé la invitación y activación de un profesional desde la cuenta del jefe. El profesional ordinario no pudo invitar a otros profesionales y permaneció sin pacientes ni exámenes al no tener asignaciones. Estos recorridos fueron confirmados en Windows. (José Aránguiz)

Conservo pendientes de comprobación manual la reutilización de un código consumido y la revocación de una invitación antes de activarla. Sus condiciones tienen cobertura automatizada y del verificador, pero no las presento como recorridos manuales ya realizados. No incorporé correos, contraseñas ni códigos de las pruebas a la documentación. Las verificaciones de concurrencia real, Docker y los demás pendientes de alcance permanecen abiertos. No modifiqué el repositorio oficial. (José Aránguiz)

## Cierre del recorrido manual de invitaciones

Comprobé que un código ya consumido no permite otra activación y conserva la cuenta existente. También emití una invitación de prueba, la revoqué antes de activarla y confirmé que su código fue rechazado. Ambos recorridos funcionaron. Con esta confirmación cierro la validación manual prevista del incremento de invitaciones, junto con los recorridos anteriores del administrador, jefe y profesional. No publiqué códigos ni contraseñas. (José Aránguiz)

Este cierre corresponde al incremento CAM-089, no a toda la fase 7.2. Conservo pendientes concurrencia real, Docker, suspensión/edición auditadas, incorporación de cuentas existentes y acreditación profesional. Los estados pendientes de los apartados anteriores describen el momento en que se registraron; la reutilización y revocación manuales ya están comprobadas. El repositorio oficial permanece sin cambios. (José Aránguiz)
