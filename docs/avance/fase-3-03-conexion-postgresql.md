# Fase 3.3 — conexión PostgreSQL

Base: fase-3/seguridad-credenciales.
Rama: fase-3/conexion-postgresql.

## Resultado
Configuración PostgreSQL local validada, pool reutilizable y comando de comprobación real con SELECT 1. Sin tablas, cuentas de Vitalia, sesiones ni cambios visuales.
Se añaden siete pruebas: valores de configuración, rechazo de entradas inválidas, campos requeridos, errores inactivos sin datos sensibles, consulta de disponibilidad, fallo de consulta y salida controlada de CLI.
El detalle de los cambios existentes autorizados está en docs/cambios-codigo/CAM-003-postgresql.md.
La instalación y creación de usuario/base las realiza el usuario con docs/postgresql-local.md.

## Estado de calidad
TypeScript y las 17 pruebas se verifican con las dependencias fijadas.
Pendiente: ejecución del comando contra PostgreSQL 16 local del usuario. El paso solo se considera validado de extremo a extremo cuando dicha ejecución es correcta.

## Próximo incremento
Persistencia de cuentas y permisos conforme al alcance documentado. Todavía no hay conexión desde el servidor HTTP hacia la base ni un inicio de sesión real.
Los archivos anteriores se conservan hasta la limpieza expresamente solicitada al final.
