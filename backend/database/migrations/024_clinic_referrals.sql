-- Estructura de derivación disponible desde 019; ampliar solo auditoría de consulta del destino.
ALTER TABLE public.vitalia_care_access_audit DROP CONSTRAINT vitalia_care_access_audit_action_check;
ALTER TABLE public.vitalia_care_access_audit ADD CHECK(action IN ('list','view','download','view_review','referral_options'));
