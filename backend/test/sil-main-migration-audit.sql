-- Auditoría previa a la consolidación del SIL en Vitalia principal.
-- SOLO METADATOS. No lee nombres, contraseñas ni datos clínicos.
-- Ejecutar en PostgreSQL del contenedor vitalia-postgres-1.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

SELECT current_database() AS base,
       current_user AS usuario,
       current_setting('transaction_read_only') AS solo_lectura;

-- Reporta TODAS las migraciones 001–037 y su estado real.
-- 036 y 037 son exclusivas de DEMO: deben permanecer ausentes.
WITH pasos AS (
  SELECT generate_series(1,37) AS numero
)
SELECT lpad(p.numero::text,3,'0') AS paso,
       COALESCE(m.version,'NO_APLICADA') AS migracion_registrada,
       CASE
         WHEN p.numero>=36 THEN 'DEMO_NO_TRASLADAR'
         WHEN p.numero BETWEEN 26 AND 35 THEN 'SIL_REVISAR_ANTES'
         WHEN p.numero=17 OR p.numero=18 THEN 'ROLES_Y_SESIONES'
         ELSE 'BASE'
       END AS categoria
FROM pasos p
LEFT JOIN public.vitalia_schema_migrations m
  ON left(m.version,3)=lpad(p.numero::text,3,'0')
ORDER BY p.numero;

-- Los roles deben ser auditados solo en estructura, no en cuentas individuales.
WITH objetos(nombre) AS (
  VALUES
    ('vitalia_roles'),
    ('vitalia_accounts'),
    ('vitalia_sessions'),
    ('vitalia_account_roles'),
    ('vitalia_professional_invitations'),
    ('vitalia_exam_assistant_threads'),
    ('vitalia_sil_orders'),
    ('vitalia_sil_external_reports')
)
SELECT nombre,
       CASE WHEN to_regclass('public.'||nombre) IS NULL
            THEN 'AUSENTE' ELSE 'PRESENTE' END AS estado
FROM objetos ORDER BY nombre;

-- Estructura de las tablas de cuentas, roles y sesiones.
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema='public'
  AND table_name IN (
    'vitalia_accounts','vitalia_sessions',
    'vitalia_account_roles','vitalia_roles'
  )
ORDER BY table_name, ordinal_position;

-- Comprueba si los mecanismos de asignación de roles están instalados.
SELECT c.relname AS tabla, t.tgname AS trigger, t.tgenabled AS habilitado
FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname IN ('vitalia_accounts','vitalia_sessions')
  AND NOT t.tgisinternal
ORDER BY c.relname,t.tgname;

COMMIT;
