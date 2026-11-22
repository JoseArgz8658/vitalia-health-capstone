CREATE TABLE public.vitalia_sil_main_sites (
 id uuid PRIMARY KEY,
 lab_id uuid NOT NULL REFERENCES public.vitalia_sil_main_laboratories(id),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 120),
 address text NOT NULL CHECK(length(btrim(address)) BETWEEN 3 AND 200),
 commune text NOT NULL CHECK(length(btrim(commune)) BETWEEN 2 AND 100),
 region text CHECK(length(btrim(region)) BETWEEN 2 AND 100),
 phone text CHECK(length(phone) BETWEEN 5 AND 32),
 email text CHECK(length(email) BETWEEN 3 AND 254),
 active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(lab_id,id)
);
CREATE UNIQUE INDEX vitalia_sil_main_sites_name_idx
 ON public.vitalia_sil_main_sites(lab_id,lower(btrim(name)));
ALTER TABLE public.vitalia_sil_main_orders ADD COLUMN site_id uuid,
 ADD FOREIGN KEY(lab_id,site_id) REFERENCES public.vitalia_sil_main_sites(lab_id,id);
ALTER TABLE public.vitalia_sil_main_pending_requests ADD COLUMN site_id uuid,
 ADD FOREIGN KEY(lab_id,site_id) REFERENCES public.vitalia_sil_main_sites(lab_id,id);
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
    'operator_invitation_revoked','site_created','site_updated','site_activated','site_deactivated'
  ));
