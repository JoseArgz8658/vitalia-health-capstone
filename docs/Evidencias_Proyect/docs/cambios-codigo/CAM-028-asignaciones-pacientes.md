# CAM-028 — Asignaciones paciente-profesional

Autorización: «autorizo crear todo aquello» tras detallar migración 007, módulos y pantallas, y cambios de app.ts, server.ts, auth_api.dart y vitalia_mvp_app.dart.

Cambios existentes: app.ts monta router opcional de asignaciones; server.ts conecta el servicio transaccional y exige tablas 007; auth_api.dart agrega solicitudes autenticadas acotadas al origen/rutas de asignaciones; vitalia_mvp_app.dart conecta las pantallas reales de administrador/profesional y conserva avisos de sesión.

Se agregan migración 007, servicio/router, comandos de migración y verificación PostgreSQL, cliente/pantalla Flutter, pruebas y documentación. No se cambian cuentas, documentos, procesamiento ni dependencias.

El administrador activa/desactiva relaciones de cuentas existentes. El profesional lista solo sus relaciones activas. Una pareja única, reactivación conserva fila, cambios reales auditados dentro de la transacción. Todavía no hay acceso a exámenes ni aprobación.

Validación: compilación TypeScript y 233 pruebas backend en 30 suites. Pruebas nuevas cubren roles, aislamiento, duplicados, reactivación, auditoría, campos forjados y paginación. Flutter SDK no disponible aquí: pruebas de API, pantallas, acceso, sesión y formato móvil añadidas, pendientes en Windows. Comprobación PostgreSQL sintética transaccional preparada para el usuario.

Reversión: restaurar los cuatro archivos existentes desde fase-5/cuentas-privilegiadas y retirar módulos/pantallas nuevos. Mantener 007 y sus datos si ya aplicada; no borrar tablas de auditoría ni editar migraciones aplicadas. La interfaz retirada no elimina relaciones. La desactivación normal se hace desde administrador.
