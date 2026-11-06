-- Verificación documental global, independiente de pertenencia y acceso clínico.
ALTER TABLE public.vitalia_clinic_memberships ADD CONSTRAINT vitalia_membership_person_identity UNIQUE(id,clinic_id,professional_person_id);
ALTER TABLE public.vitalia_professional_profiles ADD COLUMN verification_revision integer NOT NULL DEFAULT 0 CHECK(verification_revision>=0);
ALTER TABLE public.vitalia_professional_profiles ADD COLUMN verification_request_id uuid;
ALTER TABLE public.vitalia_professional_profiles ADD COLUMN verification_decided_by uuid REFERENCES public.vitalia_accounts(id);
ALTER TABLE public.vitalia_professional_profiles ADD COLUMN verification_decided_at timestamptz CHECK(isfinite(verification_decided_at));
CREATE TABLE public.vitalia_credential_requests (
 id uuid PRIMARY KEY,
 clinic_id uuid NOT NULL,
 membership_id uuid NOT NULL,
 person_id uuid NOT NULL REFERENCES public.vitalia_professional_profiles(person_id),
 requested_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 registration_reference text NOT NULL CHECK(length(btrim(registration_reference)) BETWEEN 1 AND 200),
 supporting_reference text NOT NULL CHECK(length(btrim(supporting_reference)) BETWEEN 5 AND 500),
 request_hash text NOT NULL CHECK(request_hash ~ '^[a-f0-9]{64}$'),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','verified','rejected')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(membership_id,clinic_id,person_id) REFERENCES public.vitalia_clinic_memberships(id,clinic_id,professional_person_id),
 UNIQUE(id,person_id)
);
CREATE UNIQUE INDEX vitalia_one_pending_credential ON public.vitalia_credential_requests(person_id) WHERE state='pending';
CREATE INDEX vitalia_credential_request_clinic ON public.vitalia_credential_requests(clinic_id,membership_id,created_at DESC,id);
ALTER TABLE public.vitalia_professional_profiles ADD CONSTRAINT vitalia_professional_verification_request FOREIGN KEY(verification_request_id,person_id) REFERENCES public.vitalia_credential_requests(id,person_id);
CREATE TABLE public.vitalia_credential_audit (
 id uuid PRIMARY KEY,
 request_id uuid NOT NULL UNIQUE,
 person_id uuid NOT NULL,
 actor_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 decision text NOT NULL CHECK(decision IN ('verified','rejected')),
 source_reference text NOT NULL CHECK(length(btrim(source_reference)) BETWEEN 5 AND 500),
 checked_at timestamptz NOT NULL CHECK(isfinite(checked_at) AND checked_at<=CURRENT_TIMESTAMP),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 5 AND 1000),
 confirmed boolean NOT NULL CHECK(confirmed),
 request_hash text NOT NULL CHECK(request_hash ~ '^[a-f0-9]{64}$'),
 before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
 after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(request_id,person_id) REFERENCES public.vitalia_credential_requests(id,person_id)
);
CREATE TRIGGER vitalia_credential_audit_immutable BEFORE UPDATE OR DELETE ON public.vitalia_credential_audit FOR EACH ROW EXECUTE FUNCTION public.vitalia_prevent_membership_audit_change();
CREATE FUNCTION public.vitalia_guard_credential_request() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'La solicitud conserva su trazabilidad'; END IF;
 IF OLD.state<>'pending' OR NEW.state NOT IN ('verified','rejected')
 OR (to_jsonb(NEW)-'state') IS DISTINCT FROM (to_jsonb(OLD)-'state')
 OR NOT EXISTS(SELECT 1 FROM public.vitalia_credential_audit WHERE request_id=NEW.id AND decision=NEW.state)
 THEN RAISE EXCEPTION 'La solicitud requiere una decisión documentada'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER vitalia_credential_request_guard BEFORE UPDATE OR DELETE ON public.vitalia_credential_requests FOR EACH ROW EXECUTE FUNCTION public.vitalia_guard_credential_request();
-- La elegibilidad exige procedencia de verificación registrada, además del estado.
CREATE OR REPLACE FUNCTION public.vitalia_assert_care_professional(membership uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE actor uuid;
BEGIN
 SELECT p.account_id INTO actor FROM public.vitalia_clinic_memberships m
 JOIN public.vitalia_people p ON p.id=m.professional_person_id
 JOIN public.vitalia_professional_profiles f ON f.person_id=p.id
 JOIN public.vitalia_clinics c ON c.id=m.clinic_id
 JOIN public.vitalia_account_roles g ON g.account_id=p.account_id AND g.role_code='profesional' AND g.active
 JOIN public.vitalia_credential_audit a ON a.request_id=f.verification_request_id AND a.person_id=p.id
 WHERE m.id=membership AND m.active AND c.active AND f.verification_status='verified'
 AND f.registration_reference IS NOT NULL AND a.decision='verified'
 AND f.registration_reference=a.after_state->>'registrationReference'
 AND f.verification_revision=(a.after_state->>'revision')::integer
 AND f.verification_decided_by=a.actor_id AND f.verification_decided_at=a.created_at;
 IF actor IS NULL THEN RAISE EXCEPTION 'Profesional sin verificación documentada vigente'; END IF;
 RETURN actor;
END;
$$;
REVOKE ALL ON public.vitalia_credential_requests,public.vitalia_credential_audit FROM PUBLIC;
