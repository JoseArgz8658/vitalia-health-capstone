# CAM-088 — Creación y consulta institucional con trazabilidad

Añadí la gestión administrativa de clínicas y sucursales en la rama fase-7/02-clinicas-pertenencias, manteniendo intactas las migraciones 001..013, asignaciones y revisiones existentes. No modifiqué el repositorio oficial ni añadí dependencias. (José Aránguiz)

## Comportamiento

Añadí GET/POST /api/institutions y GET/POST /api/institutions/:id/branches, junto con GET /api/institutions/territories para el catálogo de los formularios. Todas las rutas exigen sesión de administrador, respuestas no-store y cuerpos/parámetros estrictos. Los listados tienen paginación de veinte registros como máximo. La identidad del actor procede de la sesión, nunca del formulario. Pacientes y profesionales no acceden a esta gestión. (José Aránguiz)

La creación de clínica permite nombre y teléfono opcional. La sucursal se crea exclusivamente bajo la clínica de la ruta y exige nombre, calle, número o S/N y comuna existente; piso, unidad y teléfono son opcionales. La región y provincia se eligen con el catálogo, conservando en la base solo la comuna. La pantalla muestra el nombre de comuna. No habilité edición, desactivación, eliminación, gestión de pertenencias ni asignación de jefes clínicos en este incremento. (José Aránguiz)

El identificador de solicitud se conserva al reintentar sin modificar el formulario. Un envío idéntico devuelve el registro existente sin otra auditoría; el mismo identificador con contenido o clínica distintos produce conflicto. Cambiar el formulario genera una solicitud nueva. La unicidad de nombres de clínica no se presupone: dos instituciones pueden compartir nombre. (José Aránguiz)

Añadí el acceso Clínicas y sucursales al icono de hospital de la barra del administrador, sin desplazar sus formularios actuales. Las pantallas abren en consulta, y Agregar clínica o Agregar sucursal habilita el formulario. Guardar informa el resultado, Cancelar descarta el borrador y un error conserva los datos para reintentar. Esta gestión no permite consultar exámenes. (José Aránguiz)

## Auditoría y permisos

Añadí 014_institution_audit, con prerrequisito 013, para registrar actor, clínica, sucursal si corresponde, acción de creación y fecha. La creación y su auditoría se realizan en una transacción: un fallo de auditoría revierte el registro. Esta tabla añade una entidad a las 31 de 013; al aplicar 014 se esperan 32 tablas. No modifiqué la migración 013 aplicada. La reserva anterior de 014 para roles era solo propuesta; el plan desplaza roles y atención a versiones posteriores. (José Aránguiz)

Preparé institutions-app.sql para concesión deliberada en vitalia_dev a vitalia_app: SELECT de instituciones y catálogo, INSERT por columnas de clínicas/sucursales y solo INSERT por columnas de auditoría. No concede UPDATE, DELETE ni lectura de auditoría, pertenencias o exámenes. La cuenta de base de datos es compartida por el backend; los controles de rol se aplican en los servicios y rutas, no mediante un usuario PostgreSQL distinto por sesión de la app. (José Aránguiz)

Los estados inactivos se muestran y se rechaza crear una sucursal bajo una clínica inactiva. No habilité cambios de estado por API, por lo que ese flujo y su coordinación concurrente requieren un incremento posterior. Las tablas de pertenencias y especialidades conservan sus permisos anteriores. No considero validada una autorización clínica por existir una institución. (José Aránguiz)

## Validación y límites

Compilé TypeScript y ejecuté npm test: 46 suites y 530 pruebas aprobadas, salida 0. Añadí casos de sesión, roles, paginación, campos rechazados, actor derivado de sesión, reintento, conflicto e interrupción por auditoría fallida. El conjunto anterior continúa aprobando. Una repetición intermedia agotó el límite de cinco segundos en dos pruebas existentes de contraseñas; no cambié su implementación ni el límite. La repetición final de npm test aprobó las 530 pruebas en 46 suites, código 0. No atribuyo el fallo intermitente a una causa no verificada. (José Aránguiz)

En PGlite aislado ejecuté el verificador de servicio: 14 comprobaciones, con reversión final. Comprobé además creación y consulta con rol PostgreSQL limitado, denegación de lectura/edición/borrado de auditoría y pertenencias, y reversión de una creación al retirar INSERT de auditoría. Los bloqueos advisory se simularon; no equivale a PostgreSQL 16, Docker ni prueba real de concurrencia. No añadí ese motor como dependencia del proyecto. (José Aránguiz)

Añadí cuatro pruebas Flutter para creación, reintento, cancelación, validación de sucursal y contrato de API. Revisé sintaxis Dart; Flutter no está instalado en el entorno de comprobación, por lo que analyze/test y revisión visual quedan pendientes en Windows. También están pendientes aplicación de 014, permisos institucionales y verificador en PostgreSQL 16 del equipo. (José Aránguiz)

## Pendientes conservados

Continúan pendientes validación Windows, gestión de estados y modificaciones con auditoría, especialidades/pertenencias por API, autorización institucional e invitaciones del primer jefe clínico, gestión de sus profesionales y atención por examen. No agregué un rol público ni un selector para adjudicarse permisos. Los exámenes previos mantienen su flujo. Conservo pendientes de auditoría/rectificación del perfil y evaluación de cobertura y rendimiento de IA. (José Aránguiz)

## Comprobación posterior en Windows y PostgreSQL

Ejecuté npm test con 530 pruebas aprobadas en 46 suites, flutter analyze sin incidencias y flutter test con 90 pruebas aprobadas, códigos 0. Apliqué 014 y recibí salida 0; ejecuté institutions-app.sql en pgAdmin con COMMIT, sin errores, en 71 ms. El verificador informó Gestión institucional: 14 comprobaciones correctas. Datos sintéticos revertidos, salida 0. (José Aránguiz)

Comprobé el recorrido desde la interfaz: creación y persistencia de clínica, creación y recuperación de sucursal, cancelación sin registro y ausencia de la gestión para paciente/profesional. Los recorridos funcionaron. La etiqueta Número o S/N generó una duda de uso: se ingresó un número válido, pero la abreviatura no resultó comprensible. (José Aránguiz)

Cambié la etiqueta a Número de la dirección y añadí un ejemplo visible y un icono de ayuda que explica que S/N significa sin número. La ayuda incluye Avenida Ejemplo 1234 y distingue los campos opcionales de piso y oficina. Revisé sintaxis Dart; la comprobación visual de este ajuste queda pendiente. No cambié el contrato, las validaciones, la base de datos ni las dependencias. Las 90 pruebas recibidas corresponden a la versión anterior a esta mejora de ayuda. (José Aránguiz)

## Ayuda breve para el número de dirección

Reemplacé la alerta por una ayuda breve que aparece al pasar el puntero sobre el icono: «Ingresa el número, por ejemplo 1234. Si no tiene, escribe S/N (sin número)». La ayuda no abre un diálogo ni requiere cerrar una ventana. En dispositivos táctiles puede consultarse manteniendo pulsado el icono. Conservé la etiqueta y el ejemplo del campo. Comprobé la sintaxis con dart format; la revisión visual en Flutter de este ajuste queda pendiente. (José Aránguiz)

## Confirmación de la ayuda contextual

Comprobé visualmente la ayuda al pasar el puntero y confirmé que el ajuste funciona correctamente. Esta confirmación completa la revisión manual pendiente de la ayuda contextual; no equivale a una nueva ejecución de las suites automatizadas. (José Aránguiz)
