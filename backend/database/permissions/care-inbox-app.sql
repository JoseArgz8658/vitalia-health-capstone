-- Ejecutar como postgres en vitalia_dev, después de 022.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='022_care_inbox') THEN RAISE EXCEPTION 'Falta 022'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='vitalia_app' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole) THEN RAISE EXCEPTION 'Revisar vitalia_app'; END IF;
END $$;
GRANT INSERT(care_id,actor_id,action) ON public.vitalia_care_access_audit TO vitalia_app;
GRANT UPDATE(status,updated_by,revision) ON public.vitalia_exam_care TO vitalia_app;
COMMIT;
