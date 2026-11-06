-- Revisar y ejecutar como administrador en vitalia_dev después de 017.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='vitalia_app' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole)
 THEN RAISE EXCEPTION 'Revisar vitalia_app'; END IF;
END $$;
GRANT SELECT ON public.vitalia_account_roles TO vitalia_app;
GRANT INSERT(account_id,role_code,grant_source,invitation_id) ON public.vitalia_account_roles TO vitalia_app;
GRANT INSERT(active_role) ON public.vitalia_sessions TO vitalia_app;
-- No conceder UPDATE(active) ni modificación de role_code/contraseña en cuentas existentes.
COMMIT;
