-- Ejecutar como postgres en vitalia_dev, después de 024.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='024_clinic_referrals') THEN RAISE EXCEPTION 'Falta 024'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='vitalia_app' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole) THEN RAISE EXCEPTION 'Revisar vitalia_app'; END IF;
END $$;
GRANT INSERT(previous_care_id) ON public.vitalia_exam_care TO vitalia_app;
GRANT INSERT(id,clinic_id,document_id,patient_id,source_care_id,target_care_id,actor_id,reason) ON public.vitalia_exam_referrals TO vitalia_app;
COMMIT;
