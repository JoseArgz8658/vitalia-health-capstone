-- Ejecutar como postgres en vitalia_dev después de 018. Conservar los permisos anteriores.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='018_mode_passwords') THEN RAISE EXCEPTION 'Falta migración 018'; END IF;
END $$;
GRANT SELECT(password_hash) ON public.vitalia_account_roles TO vitalia_app;
GRANT UPDATE(password_hash) ON public.vitalia_account_roles TO vitalia_app;
COMMIT;
