-- La explicación educativa nunca constituye una aprobación profesional.
CREATE TABLE public.vitalia_exam_explanations (
 id uuid PRIMARY KEY,
 review_id uuid NOT NULL UNIQUE REFERENCES public.vitalia_professional_reviews(id),
 document_id uuid NOT NULL REFERENCES public.vitalia_documents(id),
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 review_snapshot jsonb NOT NULL CHECK(jsonb_typeof(review_snapshot)='object'),
 status text NOT NULL CHECK(status IN ('generating','ready','failed')),
 attempt_id uuid NOT NULL,
 result jsonb,
 model text,
 prompt_version integer,
 catalog_version integer,
 elapsed_ms integer,
 approved boolean NOT NULL DEFAULT false CHECK(approved=false),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 started_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 finished_at timestamptz,
 CHECK((status='ready' AND result IS NOT NULL AND jsonb_typeof(result)='object' AND model IS NOT NULL AND prompt_version IS NOT NULL AND catalog_version IS NOT NULL AND elapsed_ms IS NOT NULL AND elapsed_ms>=0 AND finished_at IS NOT NULL)
  OR (status='generating' AND result IS NULL AND finished_at IS NULL)
  OR (status='failed' AND result IS NULL AND finished_at IS NOT NULL))
);
CREATE INDEX vitalia_exam_explanations_patient ON public.vitalia_exam_explanations(patient_id,created_at DESC);
CREATE TABLE public.vitalia_explanation_audit (
 id uuid PRIMARY KEY,
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 document_id uuid NOT NULL REFERENCES public.vitalia_documents(id),
 review_id uuid REFERENCES public.vitalia_professional_reviews(id),
 action text NOT NULL CHECK(action IN ('view','request','ready','failed')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_explanation_audit_patient ON public.vitalia_explanation_audit(patient_id,created_at DESC);
