CREATE TABLE public.vitalia_professional_access_audit (
 id uuid PRIMARY KEY,
 professional_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 assignment_id uuid NOT NULL REFERENCES public.vitalia_patient_assignments(id),
 document_id uuid REFERENCES public.vitalia_documents(id),
 processing_id uuid REFERENCES public.vitalia_document_processing(id),
 action text NOT NULL CHECK(action IN ('list','view_extraction','download')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK((action='list' AND document_id IS NULL AND processing_id IS NULL)
    OR (action='download' AND document_id IS NOT NULL AND processing_id IS NULL)
    OR (action='view_extraction' AND document_id IS NOT NULL))
);
CREATE INDEX vitalia_professional_access_patient_date
 ON public.vitalia_professional_access_audit(patient_id,created_at DESC);
CREATE INDEX vitalia_professional_access_actor_date
 ON public.vitalia_professional_access_audit(professional_id,created_at DESC);
