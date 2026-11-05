-- Trazabilidad administrativa; no contiene exámenes ni permisos clínicos.
CREATE TABLE public.vitalia_institution_audit (
 id uuid PRIMARY KEY,
 actor_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 clinic_id uuid NOT NULL REFERENCES public.vitalia_clinics(id),
 branch_id uuid,
 action text NOT NULL CHECK (action IN ('clinic_created','branch_created')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY (clinic_id,branch_id) REFERENCES public.vitalia_branches(clinic_id,id),
 CHECK ((action='clinic_created' AND branch_id IS NULL) OR (action='branch_created' AND branch_id IS NOT NULL))
);
CREATE INDEX vitalia_institution_audit_clinic_date ON public.vitalia_institution_audit(clinic_id,created_at);
