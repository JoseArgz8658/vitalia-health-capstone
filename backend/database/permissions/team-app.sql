-- Revisar y ejecutar como administrador, solo en vitalia_dev, después de 016.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='vitalia_app' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole)
 THEN RAISE EXCEPTION 'Revisar vitalia_app'; END IF;
END $$;
GRANT SELECT ON public.vitalia_membership_specialties,public.vitalia_membership_audit TO vitalia_app;
GRANT INSERT(clinic_id,membership_id,specialty_id) ON public.vitalia_membership_specialties TO vitalia_app;
GRANT DELETE ON public.vitalia_membership_specialties,public.vitalia_branch_memberships TO vitalia_app;
GRANT UPDATE(active,revision,updated_at) ON public.vitalia_clinic_memberships TO vitalia_app;
GRANT INSERT(id,clinic_id,membership_id,actor_id,action,reason,request_hash,before_state,after_state) ON public.vitalia_membership_audit TO vitalia_app;
-- SELECT del resto e INSERT de sucursales ya se concedieron deliberadamente en 015.
COMMIT;
