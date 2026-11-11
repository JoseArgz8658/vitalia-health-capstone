-- Revisión interna aislada de resultados de prueba, sin publicación a pacientes.
-- Los estados de revisión no implican un diagnóstico ni validación clínica real.
ALTER TABLE public.vitalia_sil_orders
  DROP CONSTRAINT vitalia_sil_orders_status_check;
ALTER TABLE public.vitalia_sil_orders
  ADD CONSTRAINT vitalia_sil_orders_status_check
    CHECK(status IN ('registered','sampled','results_recorded',
                     'review_rejected','review_approved'));

ALTER TABLE public.vitalia_sil_audit
  DROP CONSTRAINT vitalia_sil_audit_action_check;
ALTER TABLE public.vitalia_sil_audit
  ADD CONSTRAINT vitalia_sil_audit_action_check
    CHECK(action IN ('order_created','sample_received',
      'results_simulated','results_manual','results_corrected',
      'review_rejected','review_approved'));

CREATE INDEX vitalia_sil_orders_pending_review_idx
  ON public.vitalia_sil_orders(status,created_at DESC)
  WHERE status IN ('results_recorded','review_rejected');
