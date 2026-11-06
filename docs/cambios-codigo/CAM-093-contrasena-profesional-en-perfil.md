# CAM-093 — Contraseña profesional desde el perfil

Fecha: 29 de octubre de 2026. Rama `fase-7/02-clinicas-pertenencias`, repositorio de prueba.

## Resultado

Retiré del inicio de sesión el botón «Configurar contraseña profesional de mi cuenta de paciente» y la ruta pública de configuración. Añadí la sección **Seguridad de acceso** al perfil profesional, con cambio de contraseña actual, nueva contraseña, confirmación y casilla de aceptación. Rechacé contraseñas iguales a la actual o a la del paciente. Cerré las sesiones profesionales al guardar; conservé el acceso y la contraseña de paciente.

Para las cuentas antiguas que tienen permiso profesional activo pero aún no tienen contraseña profesional propia, acepté la contraseña de paciente únicamente para iniciar una configuración obligatoria. No emití una sesión profesional ni habilité las pantallas clínicas. Después de configurarla, solicité volver a iniciar sesión con la nueva contraseña.

Conservé la activación de invitaciones nuevas con contraseña profesional independiente y la aceptación de otra clínica con la contraseña profesional existente.

## Autorización de configuración

Creé una capacidad aleatoria de 32 bytes con cinco minutos de vigencia, máximo cinco intentos y un solo uso tras guardar. Guardé su huella SHA-256 y la cuenta en memoria del proceso, sin contraseñas. Limité el almacén a 100 capacidades vigentes y eliminé las vencidas al consultar o emitir.

La respuesta de login pendiente contiene `professionalPasswordSetup`, sin sesión ni usuario clínico. La API solo acepta esa capacidad en la operación de configuración mediante el esquema `ProfessionalSetup`; no la trata como Bearer. No envié la capacidad por URL. Revalidé la contraseña actual y los permisos activos al guardar. Una cuenta sin permiso profesional o sin permiso de paciente activo no obtiene esta configuración mediante login.

El reinicio de la API invalida las capacidades pendientes; en ese caso hay que repetir el inicio de sesión. Esta implementación local usa un único proceso. Una futura ejecución con varias instancias requerirá un almacén compartido para estas capacidades y sus límites.

Serialicé los cambios por cuenta. El hash nuevo y el cierre de sesiones se guardan en una transacción: si falla la revocación, se revierte también el cambio de contraseña. No modifiqué la credencial del paciente, las pertenencias ni los permisos de la cuenta. Para profesionales cuyo modo original es profesional, guardé el nuevo hash en su credencial por modo y dejé de aceptar la contraseña original en ese acceso.

## Validación

Comprobé compilación TypeScript y 646 pruebas backend en 51 suites. Añadí pruebas de vencimiento, intentos limitados, consumo de capacidad, ausencia de sesión clínica en login pendiente, protección de rutas y cambio de contraseña profesional con rechazo de datos inválidos.

El verificador de contraseñas por modo pasó de 39 a 49 comprobaciones. Lo ejecuté con hashes reales en PostgreSQL embebido aislado, incluyendo conservación de sesiones de paciente, revocación profesional, rechazo de contraseña anterior y cambio para un profesional cuya cuenta original ya era profesional. También comprobé ejecución con permisos limitados y reversión del hash cuando falla la revocación de sesiones. Los bloqueos consultivos son simulados en ese entorno; no equivale a una prueba de concurrencia en PostgreSQL 16.

Añadí cinco pruebas Flutter de transporte, configuración obligatoria y validación de formulario. Verifiqué formato y sintaxis Dart; Flutter no está disponible en este entorno. El análisis, las 117 pruebas Flutter previstas y la comprobación manual en Windows/PostgreSQL 16 quedan pendientes.

## Evidencia previa y ejecución

Registré para CAM-092 el respaldo `vitalia_dev_antes_018`, los resultados de Windows (632 pruebas backend y 112 Flutter), la migración 018, sus 39 comprobaciones correctas y los permisos confirmados con COMMIT (64 ms). No presenté esa evidencia como validación de la interfaz de CAM-093.

Este ajuste utiliza la migración 018 y los permisos ya concedidos. No creé migración 019 ni modifiqué migraciones aplicadas. La atención por examen continúa propuesta como 019. Documenté el flujo actualizado en [contraseñas por modo](../fase-7/contrasenas-por-modo.md). El repositorio oficial permanece fuera de este cambio.

(José Aránguiz)


## Confirmación en Windows y observación de interfaz

Registré la salida de Windows: flutter analyze sin problemas, 117 pruebas Flutter aprobadas y 646 pruebas backend en 51 suites aprobadas. El usuario confirmó que el flujo manual es funcional. La ejecución local del verificador ampliado no mostró sus mensajes en la salida compartida, por lo que no doy por confirmadas las 49 comprobaciones en PostgreSQL 16.

Registré como pendiente visual modernizar el formulario de contraseña: mejorar jerarquía, espaciado, campos y presentación, manteniendo las validaciones y el flujo ya comprobados. Esta observación no implica un fallo funcional ni declara terminada toda la fase 7.

(José Aránguiz)
