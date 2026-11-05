-- Aplicar deliberadamente como administrador en vitalia_dev; no es una migración.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base de destino inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='vitalia_app' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole)
 THEN RAISE EXCEPTION 'Revisar rol vitalia_app antes de conceder permisos'; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO vitalia_app;
GRANT SELECT ON public.vitalia_regions,public.vitalia_provinces,public.vitalia_communes TO vitalia_app;
GRANT SELECT ON public.vitalia_people,public.vitalia_person_identifiers,
 public.vitalia_patient_profiles,public.vitalia_professional_profiles TO vitalia_app;
GRANT INSERT(id,account_id,first_name,additional_names,first_surname,second_surname,birth_date,phone,preferred_commune_code)
 ON public.vitalia_people TO vitalia_app;
GRANT UPDATE(first_name,additional_names,first_surname,second_surname,birth_date,phone,preferred_commune_code,updated_at)
 ON public.vitalia_people TO vitalia_app;
GRANT INSERT(id,person_id,country_code,identifier_type,normalized_value)
 ON public.vitalia_person_identifiers TO vitalia_app;
GRANT UPDATE(normalized_value) ON public.vitalia_person_identifiers TO vitalia_app;
GRANT INSERT(person_id) ON public.vitalia_patient_profiles,public.vitalia_professional_profiles TO vitalia_app;
GRANT SELECT ON public.vitalia_patient_measurements TO vitalia_app;
GRANT INSERT(id,patient_person_id,measured_at,weight_kg,height_cm,source,recorded_by)
 ON public.vitalia_patient_measurements TO vitalia_app;
COMMIT;

