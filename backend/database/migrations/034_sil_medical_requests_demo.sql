-- Recepción de solicitudes médicas exclusivamente ficticias para la demo SIL.
-- Mantiene el flujo postanalítico y las órdenes históricas intactas.
-- No admite datos reales de pacientes ni implica verificar acreditación profesional.
CREATE TABLE public.vitalia_sil_medical_requests_demo (
  id uuid PRIMARY KEY,
  order_id uuid NOT NULL UNIQUE REFERENCES public.vitalia_sil_orders(id),
  patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
  origin_branch_code text NOT NULL REFERENCES public.vitalia_sil_branches(code),
  document_reference text NOT NULL
    CHECK(length(btrim(document_reference)) BETWEEN 3 AND 100),
  prescriber_name text NOT NULL
    CHECK(length(btrim(prescriber_name)) BETWEEN 3 AND 120),
  request_date date NOT NULL,
  file_name text NOT NULL
    CHECK(length(file_name) BETWEEN 5 AND 120),
  pdf_data bytea NOT NULL
    CHECK(octet_length(pdf_data) BETWEEN 8 AND 2097152),
  pdf_sha256 text NOT NULL
    CHECK(pdf_sha256 ~ '^[a-f0-9]{64}$'),
  patient_identity_checked boolean NOT NULL CHECK(patient_identity_checked),
  request_review_confirmed boolean NOT NULL CHECK(request_review_confirmed),
  created_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
  received_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  synthetic boolean NOT NULL DEFAULT true CHECK(synthetic),
  UNIQUE(patient_id,pdf_sha256)
);
CREATE INDEX vitalia_sil_medical_requests_patient_idx
  ON public.vitalia_sil_medical_requests_demo(patient_id,received_at DESC);

ALTER TABLE public.vitalia_sil_audit
  DROP CONSTRAINT vitalia_sil_audit_action_check;
ALTER TABLE public.vitalia_sil_audit
  ADD CONSTRAINT vitalia_sil_audit_action_check CHECK(action IN (
    'order_created','medical_request_received','medical_request_accessed','sample_received',
    'results_simulated','results_manual','results_corrected',
    'review_rejected','review_approved','external_report_attached',
    'external_report_published','external_report_downloaded'
  ));

-- La cuenta de paciente nunca se crea a partir del PDF. La recepción
-- requiere una cuenta ya verificada y una ficha sintética existente.
