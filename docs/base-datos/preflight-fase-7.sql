-- Fase 7: consulta previa de solo lectura. No contiene DDL.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT current_database() AS database_name;
SELECT version, applied_at FROM public.vitalia_schema_migrations ORDER BY version;
SELECT
 (SELECT count(*) FROM public.vitalia_accounts) AS accounts,
 (SELECT count(*) FROM public.vitalia_documents) AS documents,
 (SELECT count(*) FROM public.vitalia_professional_reviews) AS legacy_reviews,
 (SELECT count(*) FROM public.vitalia_exam_assistant_threads) AS assistant_threads;
SELECT table_name AS proposed_name_already_present
FROM information_schema.tables
WHERE table_schema='public' AND table_name IN (
 'vitalia_account_roles','vitalia_people','vitalia_person_identifiers',
 'vitalia_patient_profiles','vitalia_patient_measurements',
 'vitalia_professional_profiles','vitalia_regions','vitalia_provinces',
 'vitalia_communes','vitalia_clinics','vitalia_branches','vitalia_specialties',
 'vitalia_professional_specialties','vitalia_clinic_memberships',
 'vitalia_branch_memberships','vitalia_exam_care','vitalia_exam_referrals',
 'vitalia_care_reviews'
) ORDER BY table_name;
COMMIT;
