-- Relación administrativa; no constituye aprobación ni verificación profesional.
CREATE TABLE public.vitalia_patient_assignments (
 id uuid PRIMARY KEY,
 professional_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 active boolean NOT NULL DEFAULT true,
 created_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 updated_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 deactivated_at timestamptz,
 UNIQUE(professional_id,patient_id),
 CHECK(professional_id <> patient_id),
 CHECK((active AND deactivated_at IS NULL) OR (NOT active AND deactivated_at IS NOT NULL))
);
CREATE INDEX vitalia_patient_assignments_active_professional
 ON public.vitalia_patient_assignments(professional_id,patient_id) WHERE active;
CREATE TABLE public.vitalia_assignment_audit (
 id uuid PRIMARY KEY,
 assignment_id uuid NOT NULL REFERENCES public.vitalia_patient_assignments(id),
 actor_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 action text NOT NULL CHECK(action IN ('activate','deactivate')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
