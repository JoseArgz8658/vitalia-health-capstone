# Fase 3.7 — registro de pacientes

Base: fase-3/sesiones-acceso.
Rama: fase-3/registro-pacientes.

## Evidencia previa
El usuario confirmó 61 pruebas y el flujo real de sesiones. Autorizó los cambios en app.ts/server.ts y la contraseña mínima propuesta de 12 caracteres.

## Resultado
POST /api/auth/register guarda pacientes con contraseña protegida, rechaza roles/campos extra y no sobrescribe cuentas existentes.
Respuesta neutral para un registro con datos válidos, sin sesión ni identidad. La verificación de correo aún no está implementada.
Solo dos archivos previos modificados; resto de código nuevo. Sin dependencias ni migraciones adicionales.

## Calidad
TypeScript y 74 pruebas en 13 suites.
Pendiente en equipo del usuario: verify-registration-api.js, que verifica el registro y acceso reales con datos sintéticos y revierte la transacción.
Se conservan los 61 casos anteriores, rutas previas y cierre de PostgreSQL.

## Documentación
docs/registro-pacientes.md y docs/cambios-codigo/CAM-005-registro-pacientes.md.
Siguiente paso: conexión de Flutter, con autorización previa de cambios/dependencias existentes. No tocar demos ni archivos sin uso hasta la limpieza final solicitada.
