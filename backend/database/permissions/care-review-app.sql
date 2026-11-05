-- Ejecutar como postgres en vitalia_dev, después de 023.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='023_care_review_registry') THEN RAISE EXCEPTION 'Falta 023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='vitalia_app' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole) THEN RAISE EXCEPTION 'Revisar vitalia_app'; END IF;
END $$;
GRANT SELECT ON public.vitalia_approved_review_refs,public.vitalia_current_approved_reviews TO vitalia_app;
GRANT INSERT(id,document_id,patient_id,legacy_review_id,care_review_id) ON public.vitalia_approved_review_refs TO vitalia_app;
GRANT INSERT(id,care_id,document_id,patient_id,processing_id,reviewer_membership_id,reviewer_id,original_extraction,reviewed_extraction,observations,confirmed_original)
 ON public.vitalia_care_reviews TO vitalia_app;
GRANT EXECUTE ON FUNCTION public.vitalia_lock_review_processing(uuid,uuid) TO vitalia_app;
COMMIT;
