-- Informes externos YA autorizados por el laboratorio; recepción postanalítica.
-- Almacenamiento bytea limitado a 2 MiB, SOLO prototipo aislado sin datos reales.
CREATE TABLE public.vitalia_sil_external_reports (
  id uuid PRIMARY KEY,
  order_id uuid NOT NULL UNIQUE REFERENCES public.vitalia_sil_orders(id),
  patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
  file_name text NOT NULL CHECK(length(file_name) BETWEEN 5 AND 120),
  pdf_data bytea NOT NULL CHECK(octet_length(pdf_data) BETWEEN 8 AND 2097152),
  pdf_sha256 text NOT NULL CHECK(pdf_sha256 ~ '^[a-f0-9]{64}$'),
  issuing_laboratory text NOT NULL CHECK(length(btrim(issuing_laboratory)) BETWEEN 3 AND 120),
  external_authorization_ref text NOT NULL
    CHECK(length(btrim(external_authorization_ref)) BETWEEN 3 AND 120),
  externally_authorized_at timestamptz NOT NULL,
  patient_match_confirmed boolean NOT NULL CHECK(patient_match_confirmed),
  received_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
  received_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  published_by uuid REFERENCES public.vitalia_accounts(id),
  published_at timestamptz,
  CHECK ((published_by IS NULL AND published_at IS NULL) OR
         (published_by IS NOT NULL AND published_at IS NOT NULL))
);
CREATE INDEX vitalia_sil_external_reports_patient_idx
  ON public.vitalia_sil_external_reports(patient_id,published_at DESC)
  WHERE published_at IS NOT NULL;

ALTER TABLE public.vitalia_sil_orders DROP CONSTRAINT vitalia_sil_orders_status_check;
ALTER TABLE public.vitalia_sil_orders ADD CONSTRAINT vitalia_sil_orders_status_check
  CHECK(status IN ('registered','sampled','results_recorded',
    'review_rejected','review_approved','report_attached','report_published'));

ALTER TABLE public.vitalia_sil_audit DROP CONSTRAINT vitalia_sil_audit_action_check;
ALTER TABLE public.vitalia_sil_audit ADD CONSTRAINT vitalia_sil_audit_action_check
  CHECK(action IN ('order_created','sample_received',
    'results_simulated','results_manual','results_corrected',
    'review_rejected','review_approved',
    'external_report_attached','external_report_published'));

-- Publicación de un archivo autorizado externamente no convierte los
-- resultados sintéticos internos en informes validados.
