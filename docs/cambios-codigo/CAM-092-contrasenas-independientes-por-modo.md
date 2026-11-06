# CAM-092 — Contraseñas independientes por modo

Fecha: 29 de octubre de 2026. Repositorio de prueba, rama `fase-7/02-clinicas-pertenencias`.

## Motivo y resultado

Separé la contraseña profesional adicional de la contraseña del paciente. El mismo correo conserva su identidad, historial y pertenencias; cada modo valida su propia credencial. El modo original conserva su contraseña anterior. No copié esa contraseña al permiso profesional adicional.

Al aceptar la primera invitación desde una cuenta de paciente, solicité contraseña actual, nueva contraseña profesional y confirmación. Revalidé la contraseña actual en el backend, incluso con sesión válida. Rechacé la reutilización de la contraseña del paciente y las confirmaciones diferentes. Conservé el mínimo de 12 caracteres y el límite de 1024 bytes. Guardé únicamente un hash scrypt con sal aleatoria, mediante la función existente.

Para profesionales que aceptan otra clínica, conservé su contraseña profesional: deben autenticar ese modo y revalidarla; no pueden reemplazarla desde una sesión de paciente. El nuevo secreto y la pertenencia se guardan en la misma transacción de aceptación; los rechazos no consumen la invitación.

## Cuentas anteriores y migración

Preparé `018_mode_passwords`, sin alterar migraciones aplicadas. Añadí una columna opcional de hash al permiso profesional. Mantuve el hash de la cuenta como credencial de su modo original. El inicio de sesión nunca usa ese hash como alternativa para otro modo.

Las cuentas de paciente que ya tenían permiso profesional quedan pendientes de configurar la contraseña adicional. Ofrecí `/#/clave-profesional` y un enlace en el acceso profesional. Esta operación exige contraseña actual y permiso profesional activo previo; no concede roles ni requiere reutilizar una invitación consumida. Rechacé reemplazos si la contraseña profesional ya está configurada.

Cerré las sesiones de modos adicionales durante la migración, manteniendo las sesiones del modo original. La consulta de sesión también rechaza un modo adicional sin credencial propia. Serialicé la configuración por cuenta con un bloqueo transaccional, sin conceder modificación de cuentas a `vitalia_app`. El permiso nuevo permite actualizar solo la columna del hash en la tabla de permisos; no permite actualizar el rol ni su estado.

El administrador y los profesionales cuyo modo original era profesional conservan su contraseña. No creé un perfil de paciente para profesionales que no lo tenían. La recuperación y el cambio general de contraseña continúan pendientes; cuando los incorpore, deberán actuar sobre el modo correspondiente y comprobar la no reutilización. La separación de contraseñas reduce la reutilización entre accesos, pero no constituye aislamiento entre bases de datos.

## Validación

Comprobé compilación TypeScript y 632 pruebas en 50 suites. Añadí 15 pruebas de separación, credenciales cruzadas, configuración inicial, rechazo de reutilización y conservación de permisos. Actualicé las pruebas de aceptación y añadí una prueba Flutter para configurar una cuenta dual anterior sin invitación.

Ejecuté 39 comprobaciones con hashes reales en PostgreSQL embebido aislado: aceptación, conservación de datos personales y contraseña original, contraseñas cruzadas rechazadas, otra clínica y configuración de cuenta dual anterior. Los datos sintéticos se revierten. Comprobé también migración repetible, cierre selectivo de sesiones y permisos limitados. Ese entorno simula los bloqueos consultivos y no sustituye la comprobación de concurrencia en PostgreSQL 16.

Verifiqué la sintaxis y el formato de los cinco archivos Dart modificados. No dispongo de Flutter en este entorno: `flutter analyze`, la suite Flutter, la aplicación de 018 y la prueba manual quedan pendientes en Windows/PostgreSQL 16. No he aplicado migraciones a la base del usuario.

## Evidencia anterior comunicada por el usuario

Registré para CAM-091 el respaldo previo, la aplicación de 017, sus 27 comprobaciones correctas, los permisos confirmados con COMMIT y la prueba manual de cuentas y aceptación con el comportamiento esperado. Esa evidencia corresponde al diseño anterior con contraseña compartida; no la presento como prueba de CAM-092.

Documenté la ejecución en [contraseñas por modo](../fase-7/contrasenas-por-modo.md). El repositorio oficial no forma parte de este cambio.

(José Aránguiz)

## Evidencia local y ajuste posterior

Registré el respaldo `vitalia_dev_antes_018`, 112 pruebas Flutter y 632 backend aprobadas en Windows, la aplicación de 018, sus 39 comprobaciones correctas y los permisos con COMMIT (64 ms). El usuario solicitó después retirar el botón del inicio y gestionar la contraseña desde el perfil; ese ajuste está en CAM-093, con validación manual pendiente. (José Aránguiz)
