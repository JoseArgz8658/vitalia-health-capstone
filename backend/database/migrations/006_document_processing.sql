-- Resultado original de procesamiento; la aprobación profesional será un flujo aparte.
CREATE TABLE public.vitalia_document_processing (
  id uuid PRIMARY KEY,
  document_id uuid NOT NULL UNIQUE REFERENCES public.vitalia_documents(id),
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'processing', 'requires_review', 'rejected', 'failed')),
  model text NOT NULL CHECK (length(model) BETWEEN 1 AND 100),
  prompt_version integer NOT NULL CHECK (prompt_version > 0),
  result jsonb,
  failure_code text CHECK (failure_code IN ('processing_interrupted', 'processing_failed')),
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  started_at timestamptz,
  finished_at timestamptz,
  CHECK (
    (status = 'queued' AND started_at IS NULL AND finished_at IS NULL AND result IS NULL AND failure_code IS NULL)
    OR (status = 'processing' AND started_at IS NOT NULL AND finished_at IS NULL AND result IS NULL AND failure_code IS NULL)
    OR (status IN ('requires_review', 'rejected') AND started_at IS NOT NULL AND finished_at IS NOT NULL AND result IS NOT NULL AND failure_code IS NULL)
    OR (status = 'failed' AND started_at IS NOT NULL AND finished_at IS NOT NULL AND ((result IS NOT NULL AND failure_code IS NULL) OR (result IS NULL AND failure_code IS NOT NULL)))
  ),
  CHECK (result IS NULL OR (
    jsonb_typeof(result) = 'object'
    AND (result -> 'approved' = 'false'::jsonb) IS TRUE
    AND (result ->> 'status' = CASE WHEN status = 'failed' THEN 'service_error' ELSE status END) IS TRUE
  ))
);
CREATE INDEX vitalia_processing_pending ON public.vitalia_document_processing(created_at, id)
  WHERE status = 'queued';
