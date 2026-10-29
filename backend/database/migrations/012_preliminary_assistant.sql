-- Conversaciones educativas preliminares, independientes de la aprobación clínica.
-- Los hilos históricos aprobados conservan su review_id y su snapshot.
ALTER TABLE public.vitalia_exam_assistant_threads
 ADD COLUMN processing_id uuid REFERENCES public.vitalia_document_processing(id);
ALTER TABLE public.vitalia_exam_assistant_threads
 ALTER COLUMN review_id DROP NOT NULL;
ALTER TABLE public.vitalia_exam_assistant_threads
 ADD CONSTRAINT vitalia_assistant_one_source CHECK
 ((review_id IS NOT NULL AND processing_id IS NULL) OR
  (review_id IS NULL AND processing_id IS NOT NULL));
CREATE UNIQUE INDEX vitalia_assistant_processing_unique
 ON public.vitalia_exam_assistant_threads(processing_id)
 WHERE processing_id IS NOT NULL;
