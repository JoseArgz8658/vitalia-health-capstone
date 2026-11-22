-- SIL principal 047: acceso operativo por sede, sin cambios a membresías históricas.
-- Las membresías existentes quedan en modo 'all' para conservar sus permisos.
ALTER TABLE public.vitalia_sil_main_staff
 ADD COLUMN site_access_mode text NOT NULL DEFAULT 'all'
 CHECK(site_access_mode IN ('all','selected'));

CREATE TABLE public.vitalia_sil_main_staff_sites (
 lab_id uuid NOT NULL,
 account_id uuid NOT NULL,
 site_id uuid NOT NULL,
 PRIMARY KEY(lab_id,account_id,site_id),
 FOREIGN KEY(lab_id,account_id) REFERENCES public.vitalia_sil_main_staff(lab_id,account_id)
   ON DELETE CASCADE,
 FOREIGN KEY(lab_id,site_id) REFERENCES public.vitalia_sil_main_sites(lab_id,id)
);
CREATE INDEX vitalia_sil_main_staff_sites_site_idx
 ON public.vitalia_sil_main_staff_sites(lab_id,site_id,account_id);

-- La invitación conserva exactamente las sedes autorizadas al emitirla.
-- Durante su canje se verifica nuevamente que sigan activas y en el laboratorio.
ALTER TABLE public.vitalia_sil_main_operator_invites
 ADD COLUMN site_access_mode text NOT NULL DEFAULT 'all'
   CHECK(site_access_mode IN ('all','selected')),
 ADD COLUMN site_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
 ADD CONSTRAINT vitalia_sil_main_invite_site_scope_check
   CHECK ((site_access_mode='all' AND cardinality(site_ids)=0)
       OR (site_access_mode='selected' AND cardinality(site_ids)>0));

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
    'operator_membership_disabled','operator_membership_enabled',
    'operator_invitation_revoked','site_created','site_updated','site_activated',
    'site_deactivated','operator_sites_changed'
 ));
