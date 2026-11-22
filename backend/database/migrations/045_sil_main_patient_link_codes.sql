-- Código emitido por una cuenta paciente y canjeado tras verificar identidad.
CREATE TABLE public.vitalia_sil_main_patient_link_codes (
 id uuid PRIMARY KEY,
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 expires_at timestamptz NOT NULL CHECK(expires_at>created_at),
 consumed_at timestamptz,
 revoked_at timestamptz,
 lab_id uuid REFERENCES public.vitalia_sil_main_laboratories(id),
 CHECK((consumed_at IS NULL)=(lab_id IS NULL))
);
CREATE INDEX vitalia_sil_main_patient_link_codes_patient_idx
 ON public.vitalia_sil_main_patient_link_codes(patient_id,created_at DESC);
