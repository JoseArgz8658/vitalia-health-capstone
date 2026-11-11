-- Corrección incremental: la descarga por el paciente debe quedar auditada.
-- La migración 031 ya puede estar aplicada; no modificarla ni reconstruir tablas.
ALTER TABLE public.vitalia_sil_audit
  DROP CONSTRAINT vitalia_sil_audit_action_check;
ALTER TABLE public.vitalia_sil_audit
  ADD CONSTRAINT vitalia_sil_audit_action_check
    CHECK(action IN (
      'order_created',
      'sample_received',
      'results_simulated',
      'results_manual',
      'results_corrected',
      'review_rejected',
      'review_approved',
      'external_report_attached',
      'external_report_published',
      'external_report_downloaded'
    ));
