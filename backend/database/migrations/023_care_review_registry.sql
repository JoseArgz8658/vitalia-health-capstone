-- Referencia común para revisiones inmutables, sin crear asignaciones ni copiar resultados.
ALTER TABLE public.vitalia_professional_reviews ADD CONSTRAINT vitalia_legacy_review_owner UNIQUE(id,document_id,patient_id);
CREATE TABLE public.vitalia_approved_review_refs (
 id uuid PRIMARY KEY,
 document_id uuid NOT NULL,
 patient_id uuid NOT NULL,
 legacy_review_id uuid UNIQUE,
 care_review_id uuid UNIQUE,
 CHECK((legacy_review_id IS NOT NULL AND care_review_id IS NULL AND id=legacy_review_id)
    OR (care_review_id IS NOT NULL AND legacy_review_id IS NULL AND id=care_review_id)),
 FOREIGN KEY(legacy_review_id,document_id,patient_id) REFERENCES public.vitalia_professional_reviews(id,document_id,patient_id),
 FOREIGN KEY(care_review_id,document_id,patient_id) REFERENCES public.vitalia_care_reviews(id,document_id,patient_id)
);
INSERT INTO public.vitalia_approved_review_refs(id,document_id,patient_id,legacy_review_id)
 SELECT id,document_id,patient_id,id FROM public.vitalia_professional_reviews;
INSERT INTO public.vitalia_approved_review_refs(id,document_id,patient_id,care_review_id)
 SELECT id,document_id,patient_id,id FROM public.vitalia_care_reviews;
CREATE FUNCTION public.vitalia_register_approved_review() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.vitalia_approved_review_refs(id,document_id,patient_id,legacy_review_id,care_review_id)
 VALUES(NEW.id,NEW.document_id,NEW.patient_id,
  CASE WHEN TG_TABLE_NAME='vitalia_professional_reviews' THEN NEW.id ELSE NULL END,
  CASE WHEN TG_TABLE_NAME='vitalia_care_reviews' THEN NEW.id ELSE NULL END);
 RETURN NEW;
END;
$$;
CREATE TRIGGER vitalia_register_legacy_review AFTER INSERT ON public.vitalia_professional_reviews
 FOR EACH ROW EXECUTE FUNCTION public.vitalia_register_approved_review();
CREATE TRIGGER vitalia_register_care_review AFTER INSERT ON public.vitalia_care_reviews
 FOR EACH ROW EXECUTE FUNCTION public.vitalia_register_approved_review();
CREATE TRIGGER vitalia_approved_ref_immutable BEFORE UPDATE OR DELETE ON public.vitalia_approved_review_refs
 FOR EACH ROW EXECUTE FUNCTION public.vitalia_prevent_review_change();
CREATE VIEW public.vitalia_current_approved_reviews WITH (security_invoker=true) AS
 SELECT DISTINCT ON(document_id,patient_id) * FROM (
  SELECT r.id,r.document_id,r.patient_id,r.processing_id,r.reviewed_extraction,r.observations,r.created_at,r.reviewer_id,r.approved
   FROM public.vitalia_professional_reviews r JOIN public.vitalia_approved_review_refs x ON x.legacy_review_id=r.id
   WHERE r.approved
  UNION ALL
  SELECT r.id,r.document_id,r.patient_id,r.processing_id,r.reviewed_extraction,r.observations,r.created_at,r.reviewer_id,r.approved
   FROM public.vitalia_care_reviews r JOIN public.vitalia_approved_review_refs x ON x.care_review_id=r.id
   JOIN public.vitalia_exam_care c ON c.id=r.care_id AND c.status='completed'
   WHERE r.approved
 ) approved ORDER BY document_id,patient_id,created_at DESC,id DESC;
ALTER TABLE public.vitalia_exam_explanations DROP CONSTRAINT vitalia_exam_explanations_review_id_fkey;
ALTER TABLE public.vitalia_exam_explanations ADD FOREIGN KEY(review_id) REFERENCES public.vitalia_approved_review_refs(id);
ALTER TABLE public.vitalia_explanation_audit DROP CONSTRAINT vitalia_explanation_audit_review_id_fkey;
ALTER TABLE public.vitalia_explanation_audit ADD FOREIGN KEY(review_id) REFERENCES public.vitalia_approved_review_refs(id);
ALTER TABLE public.vitalia_exam_assistant_threads DROP CONSTRAINT vitalia_exam_assistant_threads_review_id_fkey;
ALTER TABLE public.vitalia_exam_assistant_threads ADD FOREIGN KEY(review_id) REFERENCES public.vitalia_approved_review_refs(id);
ALTER TABLE public.vitalia_care_access_audit DROP CONSTRAINT vitalia_care_access_audit_action_check;
ALTER TABLE public.vitalia_care_access_audit ADD CHECK(action IN ('list','view','download','view_review'));
ALTER TABLE public.vitalia_care_access_audit DROP CONSTRAINT vitalia_care_access_audit_check;
ALTER TABLE public.vitalia_care_access_audit ADD CHECK((action='list' AND care_id IS NULL) OR (action<>'list' AND care_id IS NOT NULL));
REVOKE ALL ON public.vitalia_approved_review_refs,public.vitalia_current_approved_reviews FROM PUBLIC;
-- Bloqueo de procesamiento para aprobar, sin conceder edición de resultados a la API.
CREATE FUNCTION public.vitalia_lock_review_processing(processing uuid,document uuid) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM 1 FROM public.vitalia_document_processing WHERE id=processing AND document_id=document FOR UPDATE;
END;
$$;
REVOKE ALL ON FUNCTION public.vitalia_lock_review_processing(uuid,uuid) FROM PUBLIC;
