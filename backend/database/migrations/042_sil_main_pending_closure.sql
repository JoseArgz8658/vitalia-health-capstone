-- SIL principal: cierre administrativo de derivaciones pendientes (sin orden).
-- Motivos codificados: no registrar diagnósticos, identidad ni datos clínicos
-- en texto libre o en auditoría. Se preserva el PDF para trazabilidad interna.
ALTER TABLE public.vitalia_sil_main_pending_requests
  ADD COLUMN closed_by uuid REFERENCES public.vitalia_accounts(id),
  ADD COLUMN closed_at timestamptz,
  ADD COLUMN closure_reason text
    CHECK (closure_reason IN (
      'unreadable_document','duplicate_request','incorrect_information',
      'patient_mismatch','request_withdrawn','other'
    ));

ALTER TABLE public.vitalia_sil_main_pending_requests
  DROP CONSTRAINT vitalia_sil_main_pending_requests_status_check,
  ADD CONSTRAINT vitalia_sil_main_pending_requests_status_check
    CHECK (status IN ('pending','completed','cancelled'));

ALTER TABLE public.vitalia_sil_main_pending_requests
  DROP CONSTRAINT vitalia_sil_main_pending_requests_check,
  ADD CONSTRAINT vitalia_sil_main_pending_requests_check CHECK (
    (status='pending' AND order_id IS NULL AND completed_by IS NULL
      AND completed_at IS NULL AND closed_by IS NULL
      AND closed_at IS NULL AND closure_reason IS NULL)
    OR
    (status='completed' AND order_id IS NOT NULL AND completed_by IS NOT NULL
      AND completed_at IS NOT NULL AND closed_by IS NULL
      AND closed_at IS NULL AND closure_reason IS NULL)
    OR
    (status='cancelled' AND order_id IS NULL AND completed_by IS NULL
      AND completed_at IS NULL AND closed_by IS NOT NULL
      AND closed_at IS NOT NULL AND closure_reason IS NOT NULL)
  );

ALTER TABLE public.vitalia_sil_main_audit
  DROP CONSTRAINT vitalia_sil_main_audit_action_check,
  ADD CONSTRAINT vitalia_sil_main_audit_action_check CHECK(action IN (
    'laboratory_created','operator_invited','operator_activated','staff_granted',
    'operator_review_permission_changed','patient_identity_linked',
    'order_created','medical_request_received','medical_request_downloaded',
    'report_attached','report_review_accessed','report_published','report_downloaded',
    'sample_received','results_recorded','results_approved','results_returned',
    'patient_invited','patient_activated',
    'pending_request_saved','pending_request_downloaded',
    'pending_request_completed','pending_request_cancelled'
  ));

CREATE INDEX vitalia_sil_main_pending_closed_lab_idx
  ON public.vitalia_sil_main_pending_requests(lab_id,closed_at DESC,id)
  WHERE status='cancelled';
