-- Aprobación humana separada de la salida de IA, que permanece intacta.
CREATE TABLE public.vitalia_professional_reviews (
 id uuid PRIMARY KEY,
 processing_id uuid NOT NULL UNIQUE REFERENCES public.vitalia_document_processing(id),
 document_id uuid NOT NULL REFERENCES public.vitalia_documents(id),
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 assignment_id uuid NOT NULL REFERENCES public.vitalia_patient_assignments(id),
 reviewer_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 original_extraction jsonb NOT NULL CHECK(jsonb_typeof(original_extraction)='object'),
 reviewed_extraction jsonb NOT NULL CHECK(jsonb_typeof(reviewed_extraction)='object'),
 observations text NOT NULL CHECK(length(observations)<=2000),
 confirmed_original boolean NOT NULL CHECK(confirmed_original=true),
 approved boolean NOT NULL DEFAULT true CHECK(approved=true),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_professional_reviews_patient_date
 ON public.vitalia_professional_reviews(patient_id,created_at DESC);
CREATE FUNCTION public.vitalia_prevent_review_change() RETURNS trigger
 LANGUAGE plpgsql AS $$
 BEGIN
  RAISE EXCEPTION 'Las revisiones aprobadas son inmutables.';
 END;
 $$;
CREATE TRIGGER vitalia_reviews_immutable BEFORE UPDATE OR DELETE
 ON public.vitalia_professional_reviews FOR EACH ROW
 EXECUTE FUNCTION public.vitalia_prevent_review_change();
