-- Auditoría de consulta por examen; no concede roles ni revisiones.
CREATE TABLE public.vitalia_care_access_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 care_id uuid REFERENCES public.vitalia_exam_care(id),
 actor_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 action text NOT NULL CHECK(action IN ('list','view','download')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK((action='list' AND care_id IS NULL) OR (action IN ('view','download') AND care_id IS NOT NULL))
);
CREATE INDEX vitalia_care_access_history ON public.vitalia_care_access_audit(actor_id,created_at,id);
CREATE TRIGGER vitalia_care_access_immutable BEFORE UPDATE OR DELETE ON public.vitalia_care_access_audit
 FOR EACH ROW EXECUTE FUNCTION public.vitalia_prevent_membership_audit_change();
REVOKE ALL ON public.vitalia_care_access_audit FROM PUBLIC;
