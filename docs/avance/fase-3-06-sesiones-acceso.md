# Fase 3.6 — sesiones persistentes y API de acceso

Base: fase-3/comprobacion-credenciales.
Rama: fase-3/sesiones-acceso.

## Evidencia previa
El usuario confirmó 39 pruebas, compilación y credenciales comprobadas contra PostgreSQL. Autorizó modificar app.ts/server.ts.

## Resultado
POST login, GET me y POST logout; sesiones opacas de 30 minutos con huellas persistidas; límite de intentos local y resumen de identidad sin hashes.
Migración nueva 002_sessions. No se reescribe 001_accounts ni el helper anterior.
Servidor compone una sola instancia del comprobador y cierra PostgreSQL al terminar.
No hay registro público, sesiones creadas de demostración para usuarios permanentes ni cambios de pantalla.

## Calidad
TypeScript y 61 pruebas en 11 suites. Pendiente en el equipo del usuario: migración 002, prueba real verify-auth-api y arranque habitual con npm start.
La prueba real revierte cuenta y sesiones sintéticas y no imprime secretos.

## Documentación
docs/acceso-sesiones.md: pasos y contrato.
docs/cambios-codigo/CAM-004-sesiones-acceso.md: modificaciones autorizadas, consecuencias y reversión.

## Pendientes
Registro de pacientes y definición de verificación/alta de profesionales y administradores. Conexión Flutter al acceso, permisos por recurso y auditoría.
La elección del modelo e integración IA sigue pospuesta; Docker también.
Las decisiones locales de expiración/límite son valores iniciales y no se declaran políticas de producción.
