-- Incorporación institucional. No cambia roles de cuentas existentes ni asignaciones clínicas.
CREATE TABLE public.vitalia_institution_authorizations (
 id uuid PRIMARY KEY,
 clinic_id uuid NOT NULL REFERENCES public.vitalia_clinics(id),
 nominee_email text NOT NULL CHECK(nominee_email = lower(btrim(nominee_email)) AND length(nominee_email) BETWEEN 3 AND 254),
 requester_name text NOT NULL CHECK(length(btrim(requester_name)) BETWEEN 1 AND 150),
 requester_position text NOT NULL CHECK(length(btrim(requester_position)) BETWEEN 1 AND 150),
 requester_contact text NOT NULL CHECK(length(btrim(requester_contact)) BETWEEN 1 AND 254),
 evidence_reference text NOT NULL CHECK(length(btrim(evidence_reference)) BETWEEN 1 AND 500),
 requested_at timestamptz NOT NULL CHECK(isfinite(requested_at) AND requested_at <= CURRENT_TIMESTAMP),
 recorded_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 verified_by uuid REFERENCES public.vitalia_accounts(id),
 verified_at timestamptz,
 revoked_at timestamptz,
 CHECK((verified_by IS NULL) = (verified_at IS NULL)),
 CHECK(verified_at IS NULL OR verified_at >= created_at),
 UNIQUE(clinic_id,id)
);
CREATE TABLE public.vitalia_professional_invitations (
 id uuid PRIMARY KEY,
 clinic_id uuid NOT NULL REFERENCES public.vitalia_clinics(id),
 authorization_id uuid,
 email text NOT NULL CHECK(email = lower(btrim(email)) AND length(email) BETWEEN 3 AND 254),
 clinical_role text NOT NULL CHECK(clinical_role IN ('jefe_clinico','profesional')),
 invited_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 expires_at timestamptz NOT NULL DEFAULT (CURRENT_TIMESTAMP + interval '48 hours'),
 revoked_at timestamptz,
 activated_at timestamptz,
 activated_account_id uuid REFERENCES public.vitalia_accounts(id),
 CHECK(expires_at > created_at AND isfinite(expires_at)),
 CHECK((activated_at IS NULL) = (activated_account_id IS NULL)),
 CHECK(activated_at IS NULL OR revoked_at IS NULL),
 CHECK((clinical_role='jefe_clinico') = (authorization_id IS NOT NULL)),
 FOREIGN KEY(clinic_id,authorization_id) REFERENCES public.vitalia_institution_authorizations(clinic_id,id),
 UNIQUE(clinic_id,id)
);
-- Una invitación vencida se revoca explícitamente antes de emitir otra al mismo correo.
CREATE UNIQUE INDEX vitalia_invitation_pending_email ON public.vitalia_professional_invitations(email) WHERE revoked_at IS NULL AND activated_at IS NULL;
CREATE TABLE public.vitalia_invitation_branches (
 clinic_id uuid NOT NULL,
 invitation_id uuid NOT NULL,
 branch_id uuid NOT NULL,
 PRIMARY KEY(invitation_id,branch_id),
 FOREIGN KEY(clinic_id,invitation_id) REFERENCES public.vitalia_professional_invitations(clinic_id,id),
 FOREIGN KEY(clinic_id,branch_id) REFERENCES public.vitalia_branches(clinic_id,id)
);
CREATE TABLE public.vitalia_invitation_specialties (
 invitation_id uuid NOT NULL REFERENCES public.vitalia_professional_invitations(id),
 specialty_id uuid NOT NULL REFERENCES public.vitalia_specialties(id),
 PRIMARY KEY(invitation_id,specialty_id)
);
CREATE TABLE public.vitalia_onboarding_audit (
 id uuid PRIMARY KEY,
 actor_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 clinic_id uuid NOT NULL REFERENCES public.vitalia_clinics(id),
 authorization_id uuid REFERENCES public.vitalia_institution_authorizations(id),
 invitation_id uuid REFERENCES public.vitalia_professional_invitations(id),
 action text NOT NULL CHECK(action IN ('authorization_recorded','authorization_verified','authorization_revoked','invitation_created','invitation_revoked','invitation_activated','specialty_created')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
