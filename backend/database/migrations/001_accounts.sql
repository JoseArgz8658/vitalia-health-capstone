-- Cuentas de acceso; los perfiles clínicos se incorporarán en otra migración.
CREATE TABLE public.vitalia_roles (
  code text PRIMARY KEY,
  CONSTRAINT vitalia_roles_code_check
    CHECK (code IN ('paciente', 'profesional', 'administrador'))
);

INSERT INTO public.vitalia_roles (code)
VALUES ('paciente'), ('profesional'), ('administrador');

CREATE TABLE public.vitalia_accounts (
  id uuid PRIMARY KEY,
  email text NOT NULL,
  password_hash text NOT NULL CHECK (length(password_hash) > 0),
  role_code text NOT NULL DEFAULT 'paciente'
    REFERENCES public.vitalia_roles (code),
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT vitalia_accounts_email_key UNIQUE (email),
  CONSTRAINT vitalia_accounts_email_normalized
    CHECK (email = lower(btrim(email)) AND length(email) BETWEEN 3 AND 254)
);
