-- Diagnóstico del rol utilizado para conectarse a PostgreSQL.
-- Solo consultas a metadatos. No crea, modifica ni elimina objetos/roles.
-- Se ejecuta dentro del contenedor postgres, identificado por POSTGRES_USER,
-- que coincide con PGUSER en compose.yaml vigente.
BEGIN TRANSACTION READ ONLY;

SELECT 'base_principal=' || (current_database() = 'vitalia')::text;

SELECT
  'rol_conexion=' ||
  CASE
    WHEN rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls
      THEN 'PRIVILEGIOS_ADMINISTRATIVOS_DETECTADOS'
    ELSE 'SIN_ATRIBUTOS_ADMINISTRATIVOS'
  END
FROM pg_catalog.pg_roles
WHERE rolname = current_user;

SELECT
  'atributos_rol=' ||
  'superuser:' || rolsuper::text || ',' ||
  'createdb:' || rolcreatedb::text || ',' ||
  'createrole:' || rolcreaterole::text || ',' ||
  'replication:' || rolreplication::text || ',' ||
  'bypassrls:' || rolbypassrls::text || ',' ||
  'login:' || rolcanlogin::text
FROM pg_catalog.pg_roles
WHERE rolname = current_user;

ROLLBACK;
