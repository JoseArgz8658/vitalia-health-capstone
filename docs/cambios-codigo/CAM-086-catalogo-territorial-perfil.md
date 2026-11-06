# CAM-086 — Ubicación opcional en el perfil

Incorporé el catálogo versionado de SUBDERE y selectores dependientes de región, provincia y comuna dentro de Contacto en Mi perfil. Mantengo la ubicación opcional. Guardo solo el código de comuna en preferred_commune_code; las otras relaciones pertenecen al catálogo. Esta selección no verifica domicilio ni se envía al asistente. (José Aránguiz)

## Interfaz y API

Añadí GET /api/profile/territories, con sesión, roles paciente/profesional y Cache-Control no-store. Devuelve códigos, nombres y relaciones, sin datos personales. El servicio informa indisponibilidad si faltan tablas, permisos o el catálogo completo. El formulario conserva el código existente si falla la consulta y permite editar otros datos. Reintentar vuelve a cargar el catálogo. (José Aránguiz)

Al cambiar región descarto provincia y comuna; al cambiar provincia descarto comuna. Si se inicia una selección, se requiere completar comuna antes de guardar o pulsar Quitar ubicación. Cancelar edición restaura el perfil guardado. La vista de consulta muestra los nombres relacionados cuando el catálogo está disponible. No añadí dirección, piso, clínica ni geolocalización en este incremento. (José Aránguiz)

## Datos y permisos

Incorporé backend/database/catalogs/chile-cut-2018.json con 16 regiones, 56 provincias y 346 comunas, conservando los ceros iniciales. La fuente, fecha de consulta y huellas están en el README contiguo. La versión se declara SUBDERE-CUT-2018-v04. No afirmo que la descarga constituya una actualización territorial al 2026. (José Aránguiz)

Añadí un cargador administrativo explícito limitado a vitalia_dev. Requiere 012, verifica la huella del JSON, rechaza duplicados o jerarquías inválidas y compara filas antes de insertar. La operación usa transacción, bloqueo y reversión ante conflicto. No sobrescribo datos territoriales distintos ni elimino filas. No modifiqué 001..012, no reservé la migración 013 ni añadí dependencias. Amplié profiles-app.sql con SELECT sobre las tres tablas territoriales, sin permisos de escritura para vitalia_app. (José Aránguiz)

## Validación del incremento

Compilé TypeScript y ejecuté npm test: 44 suites, 499 pruebas aprobadas y salida 0. Los casos nuevos cubren integridad del catálogo, carga repetible, conflicto sin sobrescritura, requisito 012, reversión ante fallo, roles, sesión y parámetros rechazados. (José Aránguiz)

En PGlite aislado comprobé 14 condiciones: carga, repetición, conflicto conservado, lectura con rol limitado, guardado/lectura de Quilicura, comuna inexistente rechazada con reversión, ubicación opcional eliminable y escritura territorial denegada. Los bloqueos advisory se simularon para esta comprobación; no equivale a una prueba de concurrencia ni de PostgreSQL 16 del equipo. No añadí PGlite a las dependencias del repositorio. (José Aránguiz)

Añadí pruebas Flutter de selectores dependientes, restauración, ubicación opcional, fallo/reintento del catálogo y ruta de API. La ejecución de flutter analyze y flutter test de este incremento queda pendiente en Windows. La validación de sintaxis Dart no reemplaza estas pruebas ni una comprobación visual. (José Aránguiz)

## Medidas confirmadas antes del catálogo

Confirmé los recorridos manuales de CAM-085: cancelación sin guardar, rechazo de cero/negativos y separación entre pacientes, además del guardado y recuperación ya registrados. Las 82 pruebas Flutter recibidas corresponden a ese incremento, no al nuevo catálogo. (José Aránguiz)

## Pendientes

Continúan pendientes validación Windows y PostgreSQL 16 de este catálogo, auditoría específica de perfil/medidas y política de rectificación. Clínicas, sucursales, pertenencias, invitaciones profesionales, atención por examen y extracción/chat preliminar siguen en bloques posteriores. No modifiqué el repositorio oficial ni consideré cerrada la fase 7. (José Aránguiz)

## Validación posterior en Windows y PostgreSQL 16 — 29 de octubre de 2026

Ejecuté npm test en Windows: 44 suites y 499 pruebas aprobadas, salida 0. Ejecuté flutter analyze sin incidencias y flutter test con 86 pruebas aprobadas, salida 0. Los avisos de paquetes nuevos y console.warn de escenarios simulados no impidieron la aprobación. (José Aránguiz)

Cargué el catálogo en vitalia_dev: 16 regiones, 56 provincias y 346 comunas, código 0. Apliqué el archivo actualizado profiles-app.sql en pgAdmin; terminó con COMMIT sin errores en 55 ms. Comprobé desde la aplicación selección y guardado, persistencia al reabrir, limpieza de selecciones dependientes al cambiar región/provincia, cancelación que recupera lo guardado y Quitar ubicación con guardado opcional. Todos los recorridos informados fueron funcionales. (José Aránguiz)

Queda validado el incremento funcional de ubicación en el entorno local. Conservo para el seguimiento auditoría específica y rectificación de perfiles/medidas, compatibilidad y accesibilidad en dispositivos adicionales, así como pruebas no realizadas de otros escenarios. No declaro resuelta la seguridad de despliegue ni terminada la fase 7 completa. El repositorio oficial permanece sin cambios. (José Aránguiz)
