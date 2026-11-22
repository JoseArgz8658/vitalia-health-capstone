-- Control de acceso de operadores por laboratorio.
-- Las tablas de membresías ya tienen active/can_review_reports.
-- Sólo se amplía el catálogo de auditoría, sin modificar filas existentes.
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
    'pending_request_completed','pending_request_cancelled',
    'operator_membership_disabled','operator_membership_enabled'
  ));
