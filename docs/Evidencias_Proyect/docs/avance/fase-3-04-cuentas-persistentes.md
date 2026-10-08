# Fase 3.4 — cuentas persistentes

Base: fase-3/conexion-postgresql.
Rama: fase-3/cuentas-persistentes.

## Alcance
Archivos nuevos para migrar tablas de cuentas/roles, persistir cuentas de pacientes y consultar credenciales internas con SQL parametrizado.
No se modifica ni elimina ningún archivo existente. No se añaden dependencias, scripts npm ni variables de entorno. Las demos permanecen fuera del acceso predeterminado hasta la limpieza final.
No hay endpoints de registro, cuentas privilegiadas precreadas, sesiones ni cambios visuales.

## Diseño mínimo
UUID generado por Node, correo normalizado único, hash de contraseña, rol único y fecha timestamptz. Roles paciente/profesional/administrador.
El catálogo no concede permisos por sí solo; la autorización de rutas y recursos aún debe implementarse en backend.
El repositorio actual solo crea pacientes. El alta/verificación de profesionales y la provisión administrativa requieren definir sus flujos antes de exponerlos.
No se permite elegir un rol privilegiado mediante la función de creación de paciente.
Los perfiles clínicos no se confunden con las cuentas de acceso: aún están pendientes.

## Migración
001_accounts.sql, transacción, registro de versión/huella y bloqueo transaccional para ejecuciones concurrentes.
Repetir el comando con la misma huella no repite el DDL. Una huella diferente causa rechazo sin borrar datos.
La huella normaliza CRLF/LF. Una migración aplicada no debe reescribirse; una nueva fase añadirá migraciones nuevas.
Las consultas usan el mismo cliente durante la transacción y lo liberan al terminar.

## Calidad
TypeScript y 32 pruebas en cinco suites; incluyen errores y reversión de migración, correo duplicado, hash oculto en resúmenes, consultas parametrizadas, rechazo de entradas inválidas y compatibilidad de saltos de línea.
Los 17 casos anteriores se mantienen.
Pendiente en el equipo del usuario: aplicar la migración, repetirla y ejecutar verify-accounts para comprobar persistencia real.
La verificación real crea solo datos sintéticos dentro de una transacción revertida; no deja una cuenta permanente.

## Instrucciones
docs/cuentas-postgresql.md. Mantener .env únicamente local.

## Próximo paso
Registro e inicio de sesión reales con permisos, límites de intentos y sesiones. Requerirá autorizar cualquier cambio a las rutas, composición del servidor o dependencias existentes antes de aplicarlo.
