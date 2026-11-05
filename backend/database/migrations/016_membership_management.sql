-- Gestión por clínica; no modifica credenciales ni atribuye institución a exámenes históricos.
ALTER TABLE public.vitalia_clinic_memberships ADD COLUMN revision integer NOT NULL DEFAULT 0 CHECK(revision >= 0);
CREATE TABLE public.vitalia_membership_specialties (
 clinic_id uuid NOT NULL,
 membership_id uuid NOT NULL,
 specialty_id uuid NOT NULL REFERENCES public.vitalia_specialties(id),
 PRIMARY KEY(membership_id,specialty_id),
 FOREIGN KEY(clinic_id,membership_id) REFERENCES public.vitalia_clinic_memberships(clinic_id,id)
);
-- Solo relaciones con procedencia explícita: invitación activada de esa cuenta y clínica.
INSERT INTO public.vitalia_membership_specialties(clinic_id,membership_id,specialty_id)
SELECT DISTINCT m.clinic_id,m.id,s.specialty_id
FROM public.vitalia_professional_invitations i
JOIN public.vitalia_invitation_specialties s ON s.invitation_id=i.id
JOIN public.vitalia_people p ON p.account_id=i.activated_account_id
JOIN public.vitalia_clinic_memberships m ON m.professional_person_id=p.id AND m.clinic_id=i.clinic_id
WHERE i.activated_at IS NOT NULL
ON CONFLICT DO NOTHING;
CREATE TABLE public.vitalia_membership_audit (
 id uuid PRIMARY KEY,
 clinic_id uuid NOT NULL,
 membership_id uuid NOT NULL,
 actor_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 action text NOT NULL CHECK(action='membership_updated'),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 5 AND 500),
 request_hash text NOT NULL CHECK(request_hash ~ '^[a-f0-9]{64}$'),
 before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
 after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(clinic_id,membership_id) REFERENCES public.vitalia_clinic_memberships(clinic_id,id)
);
CREATE INDEX vitalia_membership_audit_history ON public.vitalia_membership_audit(clinic_id,membership_id,created_at DESC,id);
CREATE FUNCTION public.vitalia_prevent_membership_audit_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'La auditoría de pertenencias no admite modificación o eliminación'; END;
$$;
CREATE TRIGGER vitalia_membership_audit_immutable BEFORE UPDATE OR DELETE ON public.vitalia_membership_audit
FOR EACH ROW EXECUTE FUNCTION public.vitalia_prevent_membership_audit_change();
