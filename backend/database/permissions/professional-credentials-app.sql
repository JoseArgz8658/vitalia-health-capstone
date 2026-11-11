-- Ejecutar como postgres en vitalia_dev, después de 020.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='020_professional_credentials') THEN RAISE EXCEPTION 'Falta 020'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='vitalia_app' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole) THEN RAISE EXCEPTION 'Revisar vitalia_app'; END IF;
END $$;
GRANT SELECT ON public.vitalia_credential_requests,public.vitalia_credential_audit TO vitalia_app;
GRANT INSERT(id,clinic_id,membership_id,person_id,requested_by,registration_reference,supporting_reference,request_hash) ON public.vitalia_credential_requests TO vitalia_app;
GRANT UPDATE(state) ON public.vitalia_credential_requests TO vitalia_app;
GRANT INSERT(id,request_id,person_id,actor_id,decision,source_reference,checked_at,reason,confirmed,request_hash,before_state,after_state) ON public.vitalia_credential_audit TO vitalia_app;
GRANT UPDATE(verification_status,registration_reference,verification_revision,verification_request_id,verification_decided_by,verification_decided_at,updated_at) ON public.vitalia_professional_profiles TO vitalia_app;
COMMIT;
