-- La base guarda solo la huella del token; la expiración no se renueva automáticamente.
CREATE TABLE public.vitalia_sessions (
  token_hash text PRIMARY KEY CHECK (token_hash ~ '^[a-f0-9]{64}$'),
  account_id uuid NOT NULL REFERENCES public.vitalia_accounts (id),
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at timestamptz NOT NULL,
  CONSTRAINT vitalia_sessions_expiry_check CHECK (expires_at > created_at)
);
