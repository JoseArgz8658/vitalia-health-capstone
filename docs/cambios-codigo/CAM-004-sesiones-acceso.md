# CAM-004 — integrar sesiones y rutas de acceso

## Autorización
El usuario autorizó modificar backend/src/app.ts y backend/src/server.ts para incorporar rutas, PostgreSQL, autenticación y cierre de conexiones.

## Cambios existentes
app.ts incorpora createAuthRouter y un parámetro opcional AuthServices. Monta /api/auth antes del 404.
Mantiene health, límite JSON, 404 y manejo de errores existentes. createApp() sin servicios conserva el comportamiento anterior para pruebas.
server.ts agrega inicialización asíncrona de PostgreSQL, comprobación de las tablas requeridas y una instancia de autenticación compartida. Compone los servicios de sesiones y las rutas.
Conserva host/puerto configurados, mensaje de arranque, manejo de error del puerto y señales SIGINT/SIGTERM. Extiende el cierre para liberar pool y conexiones HTTP; descarta arranque ante configuración o esquema inválido.

## Motivo y consecuencias
Sin montar las rutas antes del 404, todas las peticiones de login/me/logout serían recursos inexistentes.
Sin componer servicios PostgreSQL y autenticación al arrancar, las rutas no podrían generar ni verificar sesiones persistentes.
Ahora npm start requiere una base disponible y ambas migraciones. La indisponibilidad impide el arranque, en vez de iniciar un servidor cuyo acceso no funcionaría.
La gestión de cierre evita dejar conexiones del pool retenidas al detener el proceso.

## Archivos nuevos
Migración 002_sessions, persistencia de sesiones, router, límite de login, migrador adicional, comandos de migración/verificación y pruebas.
No se modifican dependencias, lock, .env.example, migración 001, repositorio de cuentas, hash ni comprobador de credenciales. No se eliminan archivos de demo.

## Riesgos y alcance
Los tokens son secretos del cliente y solo se entregan tras comprobar contraseña. No se registran en logs; la base solo almacena huellas.
Duración inicial 30 minutos y diez peticiones login por IP/15 minutos. Límite en memoria de una instancia; proxy/múltiples procesos, HTTPS, limpieza de sesiones expiradas y permisos de recursos siguen pendientes del despliegue.
No hay registro público ni actualización de Flutter en este cambio.

## Validación
TypeScript y 61 pruebas en 11 suites, incluyendo los 39 casos previos.
Pruebas nuevas de login, respuestas neutrales, error interno sanitizado, bearer, no-store, expiración consultada en PostgreSQL, revocación, hash de tokens, límite de intentos y arranque ante configuración inválida.
La comprobación real con PostgreSQL se entrega en verify-auth-api.js; pendiente de ejecutar en el equipo del usuario.

## Reversión
La rama fase-3/comprobacion-credenciales conserva el backend anterior.
Volver a esa rama y ejecutar npm ci restaura el servidor previo. No borrar la tabla de sesiones ni cuentas: el código anterior no la utiliza, y cualquier eliminación necesita autorización explícita.
