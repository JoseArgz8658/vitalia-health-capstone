-- Aplicar como administrador exclusivamente en vitalia_dev después de 014.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='vitalia_app' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole)
 THEN RAISE EXCEPTION 'Revisar vitalia_app'; END IF;
END $$;
GRANT SELECT ON public.vitalia_clinics,public.vitalia_branches,public.vitalia_regions,public.vitalia_provinces,public.vitalia_communes TO vitalia_app;
GRANT INSERT(id,name,contact_phone) ON public.vitalia_clinics TO vitalia_app;
GRANT INSERT(id,clinic_id,commune_code,name,street,address_number,floor,unit,contact_phone) ON public.vitalia_branches TO vitalia_app;
GRANT INSERT(id,actor_id,clinic_id,branch_id,action) ON public.vitalia_institution_audit TO vitalia_app;
COMMIT;
