-- SIL principal: derivaciones PDF recibidas antes de activar una cuenta paciente.
-- Sin vínculo a cuenta hasta completar verificación humana y activación.
-- Los campos extraídos son SOLO sugerencias: no acreditan identidad clínica.
-- No modifica registros históricos ni crea cuentas ficticias.
CREATE TABLE public.vitalia_sil_main_pending_requests (
  id uuid PRIMARY KEY,
  lab_id uuid NOT NULL REFERENCES public.vitalia_sil_main_laboratories(id),
  uploaded_by uuid NOT NULL,
  patient_email text
    CHECK (patient_email IS NULL OR
      (patient_email=lower(btrim(patient_email)) AND
       length(patient_email) BETWEEN 3 AND 254)),
  file_name text NOT NULL
    CHECK (length(btrim(file_name)) BETWEEN 5 AND 120
      AND file_name ~* '[.]pdf$'),
  pdf_data bytea NOT NULL
    CHECK (octet_length(pdf_data) BETWEEN 8 AND 2097152),
  pdf_sha256 text NOT NULL CHECK (pdf_sha256 ~ '^[a-f0-9]{64}$'),
  extraction_status text NOT NULL
    CHECK (extraction_status IN ('text_ready','needs_ocr','rejected')),
  suggestions_json jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(suggestions_json)='object'),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','completed')),
  order_id uuid,
  completed_by uuid REFERENCES public.vitalia_accounts(id),
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(lab_id,uploaded_by)
    REFERENCES public.vitalia_sil_main_staff(lab_id,account_id),
  FOREIGN KEY(order_id,lab_id)
    REFERENCES public.vitalia_sil_main_orders(id,lab_id),
  UNIQUE(lab_id,pdf_sha256),
  CHECK (
    (status='pending' AND order_id IS NULL AND completed_by IS NULL
      AND completed_at IS NULL)
    OR
    (status='completed' AND order_id IS NOT NULL AND completed_by IS NOT NULL
      AND completed_at IS NOT NULL)
  )
);
CREATE INDEX vitalia_sil_main_pending_lab_date_idx
  ON public.vitalia_sil_main_pending_requests(lab_id,created_at DESC,id)
  WHERE status='pending';

ALTER TABLE public.vitalia_sil_main_audit
  DROP CONSTRAINT vitalia_sil_main_audit_action_check,
  ADD CONSTRAINT vitalia_sil_main_audit_action_check CHECK(action IN (
    'laboratory_created','operator_invited','operator_activated','staff_granted',
    'operator_review_permission_changed','patient_identity_linked',
    'order_created','medical_request_received','medical_request_downloaded',
    'report_attached','report_review_accessed','report_published','report_downloaded',
    'sample_received','results_recorded','results_approved','results_returned',
    'patient_invited','patient_activated',
    'pending_request_saved','pending_request_downloaded','pending_request_completed'
  ));
