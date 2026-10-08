# Fase 3.5 — comprobación de credenciales

Base: fase-3/cuentas-persistentes.
Rama: fase-3/comprobacion-credenciales.

## Evidencia recibida
El usuario confirmó PostgreSQL conectado, migración aplicada y persistencia sintética correcta. El fallo anterior era el servicio postgresql-x64-16 detenido; iniciarlo resolvió la conexión y la migración.

## Archivos nuevos
- backend/src/auth/credentials.ts: comprobación interna de correo/contraseña y resumen de identidad.
- backend/test/credentials.test.cjs: siete casos nuevos.
- backend/src/database/verify-credentials.ts: comprobación real dentro de una transacción revertida.
- docs/credenciales-backend.md: ejecución y solución del servicio detenido.

No se modifica ni elimina código anterior, ni se añaden dependencias o migraciones.
No hay sesiones, tokens, registro público ni conexión de Flutter.

## Calidad
TypeScript y 39 pruebas en seis suites. Incluye rechazo de campos extra, contraseña incorrecta, cuenta inexistente, conservación de espacios, errores internos y límite de concurrencia.
Los 32 casos anteriores se conservan.
La prueba con PostgreSQL real queda pendiente del equipo del usuario.

## Límites
Resultado null neutral ante credenciales incorrectas. Hash ficticio para cuentas inexistentes, sin prometer tiempo constante para el flujo.
Máximo un cálculo concurrente por instancia; se requiere una instancia compartida y límite de intentos antes de exponerlo por HTTP.
El acceso a pantallas y recursos sigue pendiente de sesiones y permisos de backend.
