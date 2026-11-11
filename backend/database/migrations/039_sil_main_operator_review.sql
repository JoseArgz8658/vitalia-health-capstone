-- La revisión es un permiso por laboratorio sobre la membresía de operador.
-- Las asignaciones históricas se conservan sin transferir sus permisos.
ALTER TABLE public.vitalia_sil_main_staff
 ADD COLUMN can_review_reports boolean NOT NULL DEFAULT false,
 ADD CONSTRAINT vitalia_sil_main_operator_review_only
   CHECK (NOT can_review_reports OR kind='operator');

ALTER TABLE public.vitalia_sil_main_audit
 DROP CONSTRAINT vitalia_sil_main_audit_action_check,
 ADD CONSTRAINT vitalia_sil_main_audit_action_check CHECK(action IN (
   'laboratory_created','operator_invited','operator_activated',
   'staff_granted','operator_review_permission_changed',
   'patient_identity_linked','order_created',
   'medical_request_received','medical_request_downloaded',
   'report_attached','report_review_accessed',
   'report_published','report_downloaded'));

CREATE INDEX vitalia_sil_main_review_access_idx
 ON public.vitalia_sil_main_audit(lab_id,order_id,actor_id)
 WHERE action='report_review_accessed';
