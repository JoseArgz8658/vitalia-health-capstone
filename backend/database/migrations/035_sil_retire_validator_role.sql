-- Conservar cuentas históricas para la trazabilidad de las decisiones.
UPDATE public.vitalia_account_roles
SET active = false
WHERE role_code = 'validador_laboratorio' AND active;

DELETE FROM public.vitalia_sessions WHERE active_role = 'validador_laboratorio';

ALTER TABLE public.vitalia_account_roles
ADD CONSTRAINT vitalia_retired_sil_validator_inactive
CHECK (role_code <> 'validador_laboratorio' OR NOT active);
