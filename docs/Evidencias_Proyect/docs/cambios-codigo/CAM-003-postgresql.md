# CAM-003 — dependencias y configuración PostgreSQL

## Autorización
El usuario autorizó explícitamente integrar PostgreSQL y modificar backend/package.json, backend/package-lock.json y backend/.env.example.

## Cambios existentes
- package.json: agrega pg 8.23.1 y @types/pg 8.23.1. No cambia versiones anteriores ni scripts.
- package-lock.json: generado mediante npm al instalar las nuevas dependencias; conserva las versiones anteriores y agrega el conector y su árbol.
- .env.example: agrega PGHOST, PGPORT, PGDATABASE, PGUSER y PGPASSWORD vacío. No contiene secretos.

## Motivo y consecuencias
TypeScript necesita el conector y sus tipos para compilar la conexión. Sin ellos, los módulos nuevos no se pueden compilar ni ejecutar.
La configuración separa las credenciales locales del código versionado. Sin una plantilla sería más fácil configurar erróneamente la base o introducir credenciales en archivos públicos.

## Archivos nuevos
backend/src/database/{config,pool,availability,check}.ts
backend/test/database.test.cjs
docs/postgresql-local.md
docs/avance/fase-3-03-conexion-postgresql.md

## Riesgos y límites
Se añaden dependencias transitivas del conector. El pool tiene límites de conexiones y tiempos; maneja errores de clientes inactivos sin registrar sus detalles.
El alcance es loopback local sin TLS. No está habilitado para un servidor remoto ni es configuración de producción.
No se cambian app.ts, server.ts, las funciones de contraseña ni Flutter. /api/health no certifica disponibilidad de PostgreSQL.
No se eliminan demos ni archivos anteriores.

## Validación
Compilación TypeScript y 17 pruebas de tres suites. La instalación reproducible se verifica con npm ci.
La conexión a una instalación PostgreSQL real debe comprobarse en el equipo del usuario mediante el comando documentado; las pruebas automatizadas usan dobles, no una base real.

## Reversión
Volver a la rama fase-3/seguridad-credenciales y ejecutar npm ci recupera el estado anterior del backend.
Si se revierte este incremento después de integrarlo, restaurar los tres archivos existentes y retirar únicamente los archivos nuevos de este cambio requiere autorización explícita de eliminación. No borrar bases, roles ni .env del usuario.
