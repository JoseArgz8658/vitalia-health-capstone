-- Ejecutar como postgres en vitalia_dev, después de 021.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='021_care_upload') THEN RAISE EXCEPTION 'Falta 021'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='vitalia_app' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole) THEN RAISE EXCEPTION 'Revisar vitalia_app'; END IF;
END $$;
GRANT UPDATE(street,address_number,residence_commune_code) ON public.vitalia_people TO vitalia_app;
GRANT UPDATE(care_flow) ON public.vitalia_documents TO vitalia_app;
GRANT SELECT ON public.vitalia_exam_care,public.vitalia_care_contacts,public.vitalia_care_reviews,public.vitalia_exam_referrals TO vitalia_app;
GRANT INSERT(id,document_id,patient_id,clinic_id,branch_id,responsible_membership_id,specialty_id,kind,requested_by,updated_by) ON public.vitalia_exam_care TO vitalia_app;
GRANT INSERT(care_id,document_id,patient_id,residence_commune_code,consultation_commune_code,street,address_number,phone,email,confirmed) ON public.vitalia_care_contacts TO vitalia_app;
GRANT INSERT(care_id,actor_id,action,details) ON public.vitalia_care_audit TO vitalia_app;
GRANT EXECUTE ON FUNCTION public.vitalia_lock_care_selection(uuid,uuid,uuid) TO vitalia_app;
COMMIT;
