-- SIL principal: flujo POSTANALITICO multi-laboratorio.
-- No crea cuentas ficticias, no inserta laboratorios ni reutiliza tablas DEMO.
-- La migracion 038 es deliberadamente independiente de las 033-037 DEMO.
-- APLICAR SOLO mediante el migrador principal controlado y ensayado.
--
-- Una orden vincula laboratorio, paciente y personal; no representa
-- toma de muestra ni autorizacion de un resultado clinico.

CREATE TABLE public.vitalia_sil_main_laboratories (
 id uuid PRIMARY KEY,
 display_name text NOT NULL CHECK(length(btrim(display_name)) BETWEEN 3 AND 150),
 active boolean NOT NULL DEFAULT true,
 created_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE public.vitalia_sil_main_staff (
 lab_id uuid NOT NULL REFERENCES public.vitalia_sil_main_laboratories(id),
 account_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 kind text NOT NULL CHECK(kind IN ('operator','validator')),
 active boolean NOT NULL DEFAULT true,
 granted_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(lab_id,account_id),
 UNIQUE(lab_id,account_id,kind)
);
CREATE INDEX vitalia_sil_main_staff_actor_idx
 ON public.vitalia_sil_main_staff(account_id,lab_id) WHERE active;

-- Asociacion a cuenta de paciente solo tras comprobacion manual de identidad.
-- No se permite usar coincidencia de correo como verificacion clinica.
-- Invitación de operador: token de un solo uso entregado por canal
-- externo verificado. Nunca almacenar el token en texto claro.
CREATE TABLE public.vitalia_sil_main_operator_invites (
 id uuid PRIMARY KEY,
 lab_id uuid NOT NULL REFERENCES public.vitalia_sil_main_laboratories(id),
 email text NOT NULL
   CHECK(email=lower(btrim(email)) AND length(email) BETWEEN 3 AND 254),
 token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 issued_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 expires_at timestamptz NOT NULL CHECK(expires_at > created_at),
 consumed_at timestamptz,
 revoked_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_sil_main_operator_invites_email_idx
 ON public.vitalia_sil_main_operator_invites(email,lab_id)
 WHERE consumed_at IS NULL AND revoked_at IS NULL;

CREATE TABLE public.vitalia_sil_main_patients (
 lab_id uuid NOT NULL REFERENCES public.vitalia_sil_main_laboratories(id),
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 verified_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 identity_evidence_reference text NOT NULL
   CHECK(length(btrim(identity_evidence_reference)) BETWEEN 6 AND 150),
 identity_checked_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(lab_id,patient_id)
);
CREATE INDEX vitalia_sil_main_patient_idx
 ON public.vitalia_sil_main_patients(patient_id,lab_id) WHERE active;

CREATE SEQUENCE public.vitalia_sil_main_order_seq START WITH 1;

CREATE TABLE public.vitalia_sil_main_orders (
 id uuid PRIMARY KEY,
 lab_id uuid NOT NULL,
 patient_id uuid NOT NULL,
 order_number bigint NOT NULL DEFAULT nextval('public.vitalia_sil_main_order_seq'),
 status text NOT NULL DEFAULT 'registered'
   CHECK(status IN ('registered','report_attached','report_published')),
 created_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(order_number),
 UNIQUE(id,lab_id,patient_id),
 FOREIGN KEY(lab_id,patient_id)
   REFERENCES public.vitalia_sil_main_patients(lab_id,patient_id),
 FOREIGN KEY(lab_id,created_by)
   REFERENCES public.vitalia_sil_main_staff(lab_id,account_id)
);
ALTER SEQUENCE public.vitalia_sil_main_order_seq
 OWNED BY public.vitalia_sil_main_orders.order_number;
CREATE INDEX vitalia_sil_main_orders_lab_date_idx
 ON public.vitalia_sil_main_orders(lab_id,created_at DESC);
CREATE INDEX vitalia_sil_main_orders_patient_idx
 ON public.vitalia_sil_main_orders(patient_id,created_at DESC);

CREATE TABLE public.vitalia_sil_main_order_exams (
 order_id uuid NOT NULL REFERENCES public.vitalia_sil_main_orders(id),
 exam_code text NOT NULL REFERENCES public.vitalia_sil_exam_catalog(code),
 PRIMARY KEY(order_id,exam_code)
);

-- PDF externo ya autorizado, con revisión documental y publicación separadas.
-- Para el piloto el archivo se guarda en bytea, acotado a 2 MiB.
CREATE TABLE public.vitalia_sil_main_reports (
 id uuid PRIMARY KEY,
 order_id uuid NOT NULL UNIQUE,
 lab_id uuid NOT NULL,
 patient_id uuid NOT NULL,
 file_name text NOT NULL
   CHECK(length(btrim(file_name)) BETWEEN 5 AND 120 AND file_name ~* '[.]pdf$'),
 pdf_data bytea NOT NULL
   CHECK(octet_length(pdf_data) BETWEEN 8 AND 2097152),
 pdf_sha256 text NOT NULL CHECK(pdf_sha256 ~ '^[a-f0-9]{64}$'),
 issuing_laboratory text NOT NULL CHECK(length(btrim(issuing_laboratory)) BETWEEN 3 AND 150),
 external_authorization_ref text NOT NULL CHECK(length(btrim(external_authorization_ref)) BETWEEN 6 AND 150),
 authorized_professional_name text NOT NULL CHECK(length(btrim(authorized_professional_name)) BETWEEN 3 AND 150),
 externally_authorized_at timestamptz NOT NULL,
 patient_match_confirmed boolean NOT NULL CHECK(patient_match_confirmed),
 attached_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 attached_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 published_by uuid REFERENCES public.vitalia_accounts(id),
 published_at timestamptz,
 CHECK ((published_by IS NULL AND published_at IS NULL) OR
        (published_by IS NOT NULL AND published_at IS NOT NULL)),
 FOREIGN KEY(order_id,lab_id,patient_id)
   REFERENCES public.vitalia_sil_main_orders(id,lab_id,patient_id),
 FOREIGN KEY(lab_id,attached_by)
   REFERENCES public.vitalia_sil_main_staff(lab_id,account_id),
 FOREIGN KEY(lab_id,published_by)
   REFERENCES public.vitalia_sil_main_staff(lab_id,account_id)
);
CREATE INDEX vitalia_sil_main_published_patient_idx
 ON public.vitalia_sil_main_reports(patient_id,published_at DESC)
 WHERE published_at IS NOT NULL;

CREATE TABLE public.vitalia_sil_main_audit (
 id uuid PRIMARY KEY,
 lab_id uuid NOT NULL REFERENCES public.vitalia_sil_main_laboratories(id),
 order_id uuid REFERENCES public.vitalia_sil_main_orders(id),
 actor_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 action text NOT NULL CHECK(action IN (
    'laboratory_created','operator_invited','operator_activated',
    'staff_granted','patient_identity_linked','order_created',
    'report_attached','report_published','report_downloaded')),
 details jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK(jsonb_typeof(details)='object'),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_sil_main_audit_lab_idx
 ON public.vitalia_sil_main_audit(lab_id,created_at DESC,id);

-- La auditoria es de solo insercion. Impide borrar o editar eventos.
CREATE FUNCTION public.vitalia_sil_main_audit_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 RAISE EXCEPTION 'Auditoria SIL principal inmutable';
END;
$$;
CREATE TRIGGER vitalia_sil_main_audit_guard
 BEFORE UPDATE OR DELETE ON public.vitalia_sil_main_audit
 FOR EACH ROW EXECUTE FUNCTION public.vitalia_sil_main_audit_immutable();
