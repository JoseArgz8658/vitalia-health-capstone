# CAM-027 — Creación local de cuentas privilegiadas

Alcance autorizado al continuar con la creación controlada de cuentas de administrador y profesional. Solo archivos nuevos: accounts/privileged.ts, cli/secret-input.ts, database/create-privileged-account.ts, dos archivos de pruebas y documentación. No se modifica código existente, registro público, esquema, dependencias ni pantallas.

La herramienta solicita contraseña oculta y confirmación, calcula scrypt y crea la cuenta con rol explícito administrador/profesional. No actualiza cuentas existentes. Correo duplicado falla sin sustituir contraseña/rol. No añade credenciales predeterminadas ni endpoint público.

Validación: compilación TypeScript, pruebas de creación/autenticación con hashes reales y entrada de terminal. 37 pruebas aprobadas en 5 suites; terminal Linux real sin eco y con salida correcta. Persistencia y terminal PowerShell pendientes de comprobación local. El rol no representa verificación profesional; revisión y asignaciones pendientes.

Reversión: retirar los archivos nuevos y dejar de usar el comando. Las cuentas creadas permanecerán en PostgreSQL; retirar código no revierte datos ni sesiones. No eliminar manualmente cuentas relacionadas.
