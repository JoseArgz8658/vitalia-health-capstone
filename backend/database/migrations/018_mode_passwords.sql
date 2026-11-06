-- Credenciales independientes para modos adicionales. El modo original conserva su hash.
ALTER TABLE public.vitalia_account_roles ADD COLUMN password_hash text;
ALTER TABLE public.vitalia_account_roles ADD CONSTRAINT vitalia_mode_password_format CHECK (
 password_hash IS NULL OR (role_code='profesional' AND password_hash ~ '^scrypt-v1\$[a-f0-9]{32}\$[a-f0-9]{128}$')
);
-- Los modos adicionales sin contraseña propia deben configurarla antes de volver a ingresar.
DELETE FROM public.vitalia_sessions s USING public.vitalia_accounts a
WHERE s.account_id=a.id AND s.active_role<>a.role_code;
