# CAM-095 — Verificación documentada de credenciales profesionales

Continuación de la fase 7.3, repositorio de prueba, rama `fase-7/03-atencion-examen`.

## Problema y comportamiento

Separé la activación de la cuenta, la pertenencia institucional y la comprobación de credenciales. Una invitación activada no acredita por sí misma al profesional. Incorporé el registro de antecedentes y una decisión administrativa con fuente consultada, fecha, fundamento y confirmación explícita.

El jefe clínico activo registra antecedentes de las pertenencias de su clínica, incluida la suya. El administrador puede registrarlos y es quien verifica o rechaza después de contrastar la fuente. Ninguna cuenta puede aprobarse a sí misma. Elegí una decisión administrativa para la credencial global porque el mismo profesional puede pertenecer a varias clínicas: un jefe no debe modificar por sí solo una acreditación que afecta a otras instituciones.

La decisión no designa jefes clínicos, no modifica roles, contraseñas, pertenencias o asignaciones y no concede acceso a exámenes. La autorización institucional previa del primer jefe continúa por su procedimiento propio. No añadí un rol de director.

## Datos y trazabilidad

Preparé 020_professional_credentials sin modificar SQL ya aplicado. Añadí vitalia_credential_requests y vitalia_credential_audit, con versión de verificación y referencia a la decisión en el perfil profesional. El inventario pasa de 44 a 46 tablas y de 19 a 20 migraciones.

La solicitud conserva clínica, pertenencia, persona, quién registró los antecedentes, referencia de registro, respaldo y fecha. Solo puede existir una solicitud pendiente por persona. El registro de una solicitud no sustituye la verificación vigente. Las solicitudes se resuelven una vez y no se borran; la decisión queda inmutable.

La decisión conserva quién verificó, qué fuente consultó, cuándo la consultó, fundamento, estado anterior y posterior. Obtuve la cuenta del actor desde la sesión; no acepté identidad, rol, clínica o persona en el cuerpo para ampliar permisos. El rechazo modifica la elegibilidad global y queda documentado; no elimina la cuenta ni desactiva sus pertenencias.

El jefe consulta las solicitudes de su propia clínica. El estado global puede reflejar una decisión de otra institución, pero no entregué sus referencias privadas ni su historial a la jefatura de otra clínica. El administrador consulta mediante un contexto institucional concreto. Mostré los correos de quienes registraron o decidieron para que el historial sea legible.

## Seguridad y consistencia

Añadí schemas estrictos, comprobación de fechas no futuras, motivo obligatorio y confirmación. Serialicé escrituras con bloqueos transaccionales de clínica y persona, comprobé versión del perfil y registré la decisión junto con el cambio de estado en una transacción. Las solicitudes y decisiones admiten reintentos con el mismo identificador y contenido; un identificador reutilizado con otros datos se rechaza.

Endurecí la función de elegibilidad de 019 mediante CREATE OR REPLACE en 020: ahora exige una decisión verificada, referencia y revisión coincidentes y procedencia registrada. Conservé precisión de fecha enlazando el timestamp directamente desde SQL. Un campo manual verificado sin esa procedencia no basta. No cambié los valores anteriores de los perfiles al migrar.

Adapté el verificador de atención para preparar evidencia exclusivamente sintética si 020 existe; mantuve compatibilidad con 019 antes de 020. Las 54 comprobaciones de atención continúan pasando. Las funciones de elegibilidad no sustituyen la futura autorización de lectura por documento. Los controles clínicos del flujo legado no se modificaron en este incremento.

Preparé permisos por columna para vitalia_app y sin permisos de modificación o borrado de la auditoría. No concedí permisos nuevos sobre exámenes ni atenciones. El usuario de aplicación sigue sin ser propietario o superusuario. Los permisos SQL de la cuenta del backend no sustituyen el control de roles HTTP.

Esta es una revisión humana registrada: no implementé consulta automática de registros externos ni afirmé acreditación legal automática. Las referencias se muestran como texto y no se envían a IA. La verificación de identidad/RUT y la validación de especialidades requieren su procedimiento propio; no se deducen del documento de examen.

## Interfaz

Añadí Credenciales profesionales en cada tarjeta del equipo institucional. Organicé la pantalla en estado global, registro de antecedentes, revisión administrativa e historial de la clínica. La decisión no viene preseleccionada; requiere fuente, fecha de consulta, fundamento y casilla de confirmación. El jefe puede registrar antecedentes, pero no dispone del botón para resolverlos. El servidor aplica la restricción aunque se manipule la interfaz.

## Validación

Comprobé compilación TypeScript y 676 pruebas backend en 53 suites. Añadí 25 pruebas de entradas manipuladas, roles, sesión, parámetros adicionales, fallos y protección de credenciales en ejecutores.

Ejecuté la migración en PostgreSQL embebido aislado, comprobé repetición y rechazo de checksum alterado y reversión de DDL fallido. Aprobaron 46 comprobaciones con datos sintéticos revertidos y las 54 de atención por examen. Comprobé también funcionamiento con permisos limitados y reversión completa al faltar permiso de auditoría. El inventario aislado mostró 46 tablas y cero solicitudes sintéticas remanentes.

Añadí cinco pruebas Flutter de presentación, separación de facultades, confirmación y transporte. Revisé formato y sintaxis Dart. No dispongo de Flutter en este entorno: analyze, las 122 pruebas previstas y el flujo manual quedan pendientes en Windows. Tampoco he aplicado 020 a la base del usuario ni comprobado concurrencia real en PostgreSQL 16; el entorno aislado simula los bloqueos consultivos.

La guía es [credenciales profesionales](../fase-7/credenciales-profesionales.md). El catálogo y la elección por examen continúan después de esta comprobación. No modifiqué el repositorio oficial.

(José Aránguiz)

## Validación recibida en el entorno local

Registré la salida compartida de Windows: 676 pruebas backend en 53 suites, análisis Flutter sin problemas y 122 pruebas Flutter, ambos con código 0. Tras el respaldo se aplicó 020 con 46 comprobaciones de credenciales y 54 de atención correctas, con datos sintéticos revertidos. Los permisos finalizaron con COMMIT en 87 ms y el recorrido manual informado mostró el perfil profesional verificado. No extiendo esa confirmación a escenarios manuales no informados. (José Aránguiz)
