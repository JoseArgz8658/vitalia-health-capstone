-- Metadatos del documento; el contenido se almacenará en S3 privado.
CREATE TABLE public.vitalia_documents (
  id uuid PRIMARY KEY,
  patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
  exam_name text NOT NULL CHECK (length(btrim(exam_name)) BETWEEN 1 AND 100),
  exam_type text NOT NULL CHECK (exam_type IN ('Laboratorio', 'Imagenología')),
  exam_date date NOT NULL,
  original_name text NOT NULL CHECK (length(original_name) BETWEEN 1 AND 255),
  content_type text NOT NULL CHECK (content_type IN ('application/pdf', 'image/jpeg', 'image/png')),
  size_bytes integer NOT NULL CHECK (size_bytes BETWEEN 1 AND 10485760),
  storage_key text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'stored', 'failed')),
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_documents_patient_history
  ON public.vitalia_documents(patient_id, exam_date DESC, created_at DESC);
