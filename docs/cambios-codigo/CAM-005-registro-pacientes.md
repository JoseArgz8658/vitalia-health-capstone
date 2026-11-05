# CAM-005 — integrar registro de pacientes

## Autorización
El usuario autorizó modificar backend/src/app.ts y backend/src/server.ts para registro de pacientes y confirmó la contraseña mínima de 12 caracteres sin obligación de símbolos.

## Cambios existentes
app.ts agrega imports del registro, un segundo parámetro opcional PatientRegistrar y monta su router antes del 404 y del router de acceso existente.
server.ts importa createPatientRegistrar, crea una instancia con la base PostgreSQL ya inicializada y la pasa a createApp.
Las llamadas previas createApp() y createApp(auth) siguen siendo válidas.

## Motivo y consecuencias
Sin montar el router, /api/auth/register respondería 404. Sin componer el servicio con PostgreSQL, no podría guardar las cuentas.
El servidor empieza a aceptar registros reales si está ejecutándose y recibe solicitudes válidas. No crea cuentas por arrancar ni permite roles privilegiados.
La API responde neutralmente para correos duplicados, no cambia cuentas existentes ni emite sesión de registro.

## Archivos nuevos
registration.ts, registration-router.ts, pruebas de registro y comando verify-registration-api.ts; documentación de esta fase.
Se reutilizan sin modificar repository.ts, password.ts, login-limit.ts y las sesiones.
Sin cambios de dependencias, lock, .env.example ni migraciones. No se elimina código ni archivos anteriores.

## Riesgos y límites
La contraseña se conserva intacta y se guarda solo su hash. Se cuenta Unicode por puntos de código, no por unidades UTF-16.
Límite técnico 1024 bytes. Registros limitados localmente a diez/IP/15 minutos y un cálculo concurrente por instancia.
Verificación de propiedad del correo, aprovisionamiento de profesionales/admin y conexión Flutter siguen pendientes. No declarar el flujo de registro completo para producción.

## Validación
TypeScript y 74 pruebas en 13 suites, incluidos los 61 casos anteriores.
Validación de formato, campos adicionales, rol paciente, mínimo/Unicode/espacios, duplicados sin actualizaciones, respuestas sanitizadas, concurrencia y límite HTTP.
La prueba real usa datos sintéticos revertidos; pendiente de ejecución en PostgreSQL del usuario.

## Reversión
fase-3/sesiones-acceso conserva el código previo. Volver a esa rama y ejecutar npm ci restaura la API sin registro.
Las cuentas que se creen mediante el nuevo endpoint persisten: no borrarlas para revertir código. Cualquier limpieza de datos o eliminación de archivos requiere autorización explícita.
