-- Activación de portal exclusivamente para pacientes ficticios SIL.
-- Es aditiva: NO altera órdenes, cuentas, contraseñas ni fichas preexistentes.
-- Un paciente creado por el operador obtiene un registro aquí en estado pending;
-- una cuenta legada sin este registro permanece intacta.
CREATE TABLE public.vitalia_sil_portal_access_demo (
  patient_id uuid PRIMARY KEY REFERENCES public.vitalia_accounts(id),
  status text NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending','invited','active','suspended')),
  contact_confirmed_at timestamptz,
  contact_confirmed_by uuid REFERENCES public.vitalia_accounts(id),
  identity_checked_at timestamptz,
  identity_checked_by uuid REFERENCES public.vitalia_accounts(id),
  activated_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  synthetic boolean NOT NULL DEFAULT true CHECK(synthetic)
);
CREATE TABLE public.vitalia_sil_portal_invitations_demo (
  id uuid PRIMARY KEY,
  patient_id uuid NOT NULL REFERENCES public.vitalia_sil_portal_access_demo(patient_id),
  email_token_hash text NOT NULL CHECK(email_token_hash ~ '^[a-f0-9]{64}$'),
  handoff_token_hash text NOT NULL CHECK(handoff_token_hash ~ '^[a-f0-9]{64}$'),
  issued_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  revoked_at timestamptz,
  attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_sil_portal_invite_patient_idx
  ON public.vitalia_sil_portal_invitations_demo(patient_id,created_at DESC);
CREATE TABLE public.vitalia_sil_portal_audit_demo (
  id uuid PRIMARY KEY,
  patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
  actor_id uuid REFERENCES public.vitalia_accounts(id),
  action text NOT NULL CHECK(action IN (
    'patient_provisioned','invitation_sent_demo','invitation_revoked',
    'invitation_failed','portal_activated','portal_access_read'
  )),
  details jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(details)='object'),
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_sil_portal_audit_patient_idx
  ON public.vitalia_sil_portal_audit_demo(patient_id,created_at DESC,id);
