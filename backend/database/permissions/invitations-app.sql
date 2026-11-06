-- Ejecutar como administrador solo en vitalia_dev, después de 015. No aplicar sin revisar.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'vitalia_dev' THEN RAISE EXCEPTION 'Base inesperada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='vitalia_app' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole)
 THEN RAISE EXCEPTION 'Revisar vitalia_app'; END IF;
END $$;
GRANT SELECT ON public.vitalia_institution_authorizations,public.vitalia_professional_invitations,public.vitalia_invitation_branches,public.vitalia_invitation_specialties,
 public.vitalia_clinic_memberships,public.vitalia_branch_memberships,public.vitalia_specialties,public.vitalia_professional_specialties TO vitalia_app;
GRANT INSERT(id,clinic_id,nominee_email,requester_name,requester_position,requester_contact,evidence_reference,requested_at,recorded_by) ON public.vitalia_institution_authorizations TO vitalia_app;
GRANT UPDATE(verified_by,verified_at,revoked_at) ON public.vitalia_institution_authorizations TO vitalia_app;
GRANT INSERT(id,clinic_id,authorization_id,email,clinical_role,invited_by,token_hash) ON public.vitalia_professional_invitations TO vitalia_app;
GRANT UPDATE(revoked_at,activated_at,activated_account_id) ON public.vitalia_professional_invitations TO vitalia_app;
GRANT INSERT ON public.vitalia_invitation_branches,public.vitalia_invitation_specialties TO vitalia_app;
GRANT INSERT(id,actor_id,clinic_id,authorization_id,invitation_id,action) ON public.vitalia_onboarding_audit TO vitalia_app;
GRANT INSERT(id,name) ON public.vitalia_specialties TO vitalia_app;
GRANT INSERT(id,clinic_id,professional_person_id,clinical_role,active) ON public.vitalia_clinic_memberships TO vitalia_app;
GRANT INSERT(clinic_id,branch_id,membership_id) ON public.vitalia_branch_memberships TO vitalia_app;
GRANT INSERT(professional_person_id,specialty_id) ON public.vitalia_professional_specialties TO vitalia_app;
-- accounts, people y professional_profiles conservan INSERT ya requerido por los flujos anteriores.
GRANT INSERT(id,email,password_hash,role_code) ON public.vitalia_accounts TO vitalia_app;
GRANT INSERT(id,account_id,first_name,first_surname) ON public.vitalia_people TO vitalia_app;
GRANT INSERT(person_id) ON public.vitalia_professional_profiles TO vitalia_app;
COMMIT;
