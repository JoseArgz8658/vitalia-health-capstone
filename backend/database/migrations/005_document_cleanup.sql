-- Registra únicamente limpiezas confirmadas de cargas incompletas.
CREATE TABLE public.vitalia_document_cleanup (
  document_id uuid PRIMARY KEY REFERENCES public.vitalia_documents(id),
  cleaned_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
