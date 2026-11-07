-- Permiso para crear conversaciones educativas desde una extraccion preliminar.
-- Ejecutar como administrador, exclusivamente en vitalia_dev,
-- despues de la migracion 025 y de crear el rol vitalia_app.

BEGIN;

DO $$
BEGIN
  IF current_database() <> 'vitalia_dev' THEN
    RAISE EXCEPTION 'Base inesperada';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'vitalia_app'
      AND NOT rolsuper
      AND NOT rolcreatedb
      AND NOT rolcreaterole
  ) THEN
    RAISE EXCEPTION 'Rol vitalia_app no disponible o inseguro';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.vitalia_schema_migrations
    WHERE version = '025_preliminary_assistant'
  ) THEN
    RAISE EXCEPTION 'Falta migracion 025';
  END IF;
END
$$;

GRANT INSERT(processing_id)
ON public.vitalia_exam_assistant_threads
TO vitalia_app;

COMMIT;