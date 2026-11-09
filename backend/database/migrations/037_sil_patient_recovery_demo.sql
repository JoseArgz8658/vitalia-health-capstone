-- Exclusiva del portal DEMO. No modifica las credenciales existentes.
CREATE TABLE public.vitalia_sil_patient_recovery_demo (
  patient_id uuid PRIMARY KEY REFERENCES public.vitalia_accounts(id),
  key_hash text NOT NULL UNIQUE CHECK (key_hash ~ '^[a-f0-9]{64}$'),
  credential_digest text NOT NULL CHECK (credential_digest ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz NOT NULL
);

CREATE TABLE public.vitalia_sil_patient_security_audit_demo (
  id uuid PRIMARY KEY,
  patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
  action text NOT NULL CHECK (action IN ('recovery_key_generated', 'password_recovered')),
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_sil_patient_security_audit_demo_idx
  ON public.vitalia_sil_patient_security_audit_demo(patient_id, created_at DESC);
