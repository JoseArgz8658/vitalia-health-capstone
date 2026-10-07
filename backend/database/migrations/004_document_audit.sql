CREATE TABLE public.vitalia_document_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
  document_id uuid REFERENCES public.vitalia_documents(id),
  action text NOT NULL CHECK (action IN ('upload', 'list', 'download')),
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_document_audit_account_date ON public.vitalia_document_audit(account_id, created_at DESC);
