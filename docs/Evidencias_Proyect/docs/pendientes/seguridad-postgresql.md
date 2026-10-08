# Separación de roles PostgreSQL — pendiente

Compañero reporta vitalia superusuario y propietario de tablas en su entorno. Código oficial develop revisado: API usa PGUSER/PGPASSWORD, no nombre fijo. Instancia y variables privadas no inspeccionadas.

Coordinar rol vitalia_app limitado para API y worker, y cuenta propietaria/migraciones distinta. Inventariar tablas, secuencias, triggers, funciones y DDL de verificadores. Probar permisos reales, auditoría y migraciones, incluyendo Docker y reversión. No cambiar permisos todavía ni compartir credenciales. Pendiente para seguridad/datos.
