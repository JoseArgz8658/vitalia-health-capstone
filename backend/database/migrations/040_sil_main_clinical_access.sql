-- Datos nuevos, separados de las órdenes y accesos del entorno DEMO.
ALTER TABLE public.vitalia_sil_main_orders ADD UNIQUE (id,lab_id);

CREATE TABLE public.vitalia_sil_main_samples (
 order_id uuid NOT NULL,
 lab_id uuid NOT NULL,
 container_code text NOT NULL REFERENCES public.vitalia_sil_containers(code),
 barcode text NOT NULL UNIQUE,
 received_by uuid NOT NULL,
 received_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(order_id,container_code),
 FOREIGN KEY(order_id,lab_id) REFERENCES public.vitalia_sil_main_orders(id,lab_id),
 FOREIGN KEY(lab_id,received_by) REFERENCES public.vitalia_sil_main_staff(lab_id,account_id)
);
CREATE TABLE public.vitalia_sil_main_result_sets (
 order_id uuid PRIMARY KEY,
 lab_id uuid NOT NULL,
 status text NOT NULL CHECK(status IN ('pending','approved','returned')),
 values_json jsonb NOT NULL CHECK(jsonb_typeof(values_json)='array'),
 FOREIGN KEY(order_id,lab_id) REFERENCES public.vitalia_sil_main_orders(id,lab_id)
);

CREATE TABLE public.vitalia_sil_main_patient_invites (
 id uuid PRIMARY KEY,
 lab_id uuid NOT NULL,
 issued_by uuid NOT NULL,
 email text NOT NULL CHECK(email=lower(btrim(email)) AND length(email) BETWEEN 3 AND 254),
 token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 identity_reference text NOT NULL CHECK(length(btrim(identity_reference)) BETWEEN 6 AND 150),
 expires_at timestamptz NOT NULL,
 used_at timestamptz,
 FOREIGN KEY(lab_id,issued_by) REFERENCES public.vitalia_sil_main_staff(lab_id,account_id)
);

CREATE TABLE public.vitalia_sil_main_patient_recovery (
 patient_id uuid PRIMARY KEY REFERENCES public.vitalia_accounts(id),
 key_hash text NOT NULL UNIQUE CHECK(key_hash ~ '^[a-f0-9]{64}$'),
 credential_digest text NOT NULL CHECK(credential_digest ~ '^[a-f0-9]{64}$'),
 expires_at timestamptz NOT NULL
);
CREATE TABLE public.vitalia_sil_main_patient_security_audit (
 id uuid PRIMARY KEY,
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 action text NOT NULL CHECK(action IN ('recovery_key_generated','password_recovered')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.vitalia_sil_main_audit
 DROP CONSTRAINT vitalia_sil_main_audit_action_check,
 ADD CONSTRAINT vitalia_sil_main_audit_action_check CHECK(action IN (
   'laboratory_created','operator_invited','operator_activated','staff_granted',
   'operator_review_permission_changed','patient_identity_linked',
   'order_created','medical_request_received','medical_request_downloaded',
   'report_attached','report_review_accessed','report_published','report_downloaded',
   'sample_received','results_recorded','results_approved','results_returned',
   'patient_invited','patient_activated'));
