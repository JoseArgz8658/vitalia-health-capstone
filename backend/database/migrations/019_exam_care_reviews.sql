-- Base de atención por documento. No convierte asignaciones ni revisiones anteriores.
ALTER TABLE public.vitalia_documents ADD CONSTRAINT vitalia_document_owner_pair UNIQUE(id,patient_id);
ALTER TABLE public.vitalia_document_processing ADD CONSTRAINT vitalia_processing_document_pair UNIQUE(id,document_id);

CREATE TABLE public.vitalia_exam_care (
 id uuid PRIMARY KEY,
 document_id uuid NOT NULL,
 patient_id uuid NOT NULL,
 clinic_id uuid NOT NULL REFERENCES public.vitalia_clinics(id),
 branch_id uuid,
 responsible_membership_id uuid NOT NULL,
 specialty_id uuid NOT NULL REFERENCES public.vitalia_specialties(id),
 kind text NOT NULL CHECK(kind IN ('initial','referral','second_opinion','reselection')),
 previous_care_id uuid,
 prior_review_id uuid,
 status text NOT NULL DEFAULT 'requested' CHECK(status IN ('requested','active','completed','cancelled','referred')),
 requested_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 updated_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 revision integer NOT NULL DEFAULT 0 CHECK(revision>=0),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK(isfinite(created_at)),
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK(isfinite(updated_at)),
 closed_at timestamptz CHECK(isfinite(closed_at)),
 UNIQUE(id,document_id,patient_id),
 UNIQUE(id,clinic_id,document_id,patient_id),
 UNIQUE(id,responsible_membership_id),
 FOREIGN KEY(document_id,patient_id) REFERENCES public.vitalia_documents(id,patient_id),
 FOREIGN KEY(clinic_id,responsible_membership_id) REFERENCES public.vitalia_clinic_memberships(clinic_id,id),
 FOREIGN KEY(clinic_id,branch_id) REFERENCES public.vitalia_branches(clinic_id,id),
 FOREIGN KEY(previous_care_id,document_id,patient_id) REFERENCES public.vitalia_exam_care(id,document_id,patient_id),
 CHECK(previous_care_id IS NULL OR previous_care_id<>id),
 CHECK((kind='initial' AND previous_care_id IS NULL AND prior_review_id IS NULL)
    OR (kind='referral' AND previous_care_id IS NOT NULL)
    OR (kind='second_opinion' AND previous_care_id IS NOT NULL AND prior_review_id IS NOT NULL)
    OR (kind='reselection' AND previous_care_id IS NOT NULL AND prior_review_id IS NULL)),
 CHECK(updated_at>=created_at),
 CHECK((status IN ('requested','active') AND closed_at IS NULL)
    OR (status IN ('completed','cancelled','referred') AND closed_at IS NOT NULL AND closed_at>=created_at))
);
CREATE UNIQUE INDEX vitalia_exam_one_open_care ON public.vitalia_exam_care(document_id) WHERE status IN ('requested','active');
CREATE UNIQUE INDEX vitalia_exam_one_initial_care ON public.vitalia_exam_care(document_id) WHERE kind='initial';
CREATE INDEX vitalia_exam_care_patient ON public.vitalia_exam_care(patient_id,created_at DESC,id);
CREATE INDEX vitalia_exam_care_responsible ON public.vitalia_exam_care(clinic_id,responsible_membership_id,status);

CREATE TABLE public.vitalia_care_reviews (
 id uuid PRIMARY KEY,
 care_id uuid NOT NULL UNIQUE,
 document_id uuid NOT NULL,
 patient_id uuid NOT NULL,
 processing_id uuid NOT NULL,
 reviewer_membership_id uuid NOT NULL,
 reviewer_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 original_extraction jsonb NOT NULL CHECK(jsonb_typeof(original_extraction)='object'),
 reviewed_extraction jsonb NOT NULL CHECK(jsonb_typeof(reviewed_extraction)='object'),
 observations text NOT NULL CHECK(length(observations)<=2000),
 confirmed_original boolean NOT NULL CHECK(confirmed_original),
 approved boolean NOT NULL DEFAULT true CHECK(approved),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK(isfinite(created_at)),
 UNIQUE(id,document_id,patient_id),
 FOREIGN KEY(care_id,document_id,patient_id) REFERENCES public.vitalia_exam_care(id,document_id,patient_id),
 FOREIGN KEY(care_id,reviewer_membership_id) REFERENCES public.vitalia_exam_care(id,responsible_membership_id),
 FOREIGN KEY(processing_id,document_id) REFERENCES public.vitalia_document_processing(id,document_id)
);
ALTER TABLE public.vitalia_exam_care ADD CONSTRAINT vitalia_care_prior_review
 FOREIGN KEY(prior_review_id,document_id,patient_id) REFERENCES public.vitalia_care_reviews(id,document_id,patient_id);

CREATE TABLE public.vitalia_exam_referrals (
 id uuid PRIMARY KEY,
 clinic_id uuid NOT NULL REFERENCES public.vitalia_clinics(id),
 document_id uuid NOT NULL,
 patient_id uuid NOT NULL,
 source_care_id uuid NOT NULL UNIQUE,
 target_care_id uuid NOT NULL UNIQUE,
 actor_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 5 AND 500),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK(isfinite(created_at)),
 CHECK(source_care_id<>target_care_id),
 FOREIGN KEY(source_care_id,clinic_id,document_id,patient_id) REFERENCES public.vitalia_exam_care(id,clinic_id,document_id,patient_id),
 FOREIGN KEY(target_care_id,clinic_id,document_id,patient_id) REFERENCES public.vitalia_exam_care(id,clinic_id,document_id,patient_id)
);
CREATE TABLE public.vitalia_care_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 care_id uuid NOT NULL REFERENCES public.vitalia_exam_care(id),
 actor_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 action text NOT NULL CHECK(action IN ('requested','active','completed','cancelled','referred','review_approved','referral_created')),
 details jsonb NOT NULL CHECK(jsonb_typeof(details)='object'),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_care_audit_history ON public.vitalia_care_audit(care_id,created_at,id);

CREATE FUNCTION public.vitalia_assert_care_professional(membership uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE actor uuid;
BEGIN
 SELECT p.account_id INTO actor FROM public.vitalia_clinic_memberships m
 JOIN public.vitalia_people p ON p.id=m.professional_person_id
 JOIN public.vitalia_professional_profiles f ON f.person_id=p.id
 JOIN public.vitalia_clinics c ON c.id=m.clinic_id
 JOIN public.vitalia_account_roles g ON g.account_id=p.account_id AND g.role_code='profesional' AND g.active
 WHERE m.id=membership AND m.active AND c.active AND f.verification_status='verified'
 AND f.registration_reference IS NOT NULL;
 IF actor IS NULL THEN RAISE EXCEPTION 'Profesional no elegible para esta atención'; END IF;
 RETURN actor;
END;
$$;
-- Los vínculos de equipo son editables: se validan al actuar, no se fijan con FK históricas.
CREATE FUNCTION public.vitalia_assert_care_selection(membership uuid,specialty uuid,branch uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE actor uuid;
BEGIN
 actor:=public.vitalia_assert_care_professional(membership);
 IF NOT EXISTS(SELECT 1 FROM public.vitalia_membership_specialties ms JOIN public.vitalia_specialties s ON s.id=ms.specialty_id WHERE ms.membership_id=membership AND ms.specialty_id=specialty AND s.active)
 OR (branch IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.vitalia_branch_memberships bm JOIN public.vitalia_branches b ON b.id=bm.branch_id WHERE bm.membership_id=membership AND bm.branch_id=branch AND b.active))
 THEN RAISE EXCEPTION 'Especialidad o sede no vinculada al profesional'; END IF;
 RETURN actor;
END;
$$;
CREATE FUNCTION public.vitalia_guard_exam_care() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE responsible uuid; previous public.vitalia_exam_care;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'La atención conserva su trazabilidad'; END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.status<>'requested' OR NEW.revision<>0 OR NEW.updated_by<>NEW.requested_by THEN RAISE EXCEPTION 'Estado inicial inválido'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.vitalia_documents WHERE id=NEW.document_id AND patient_id=NEW.patient_id AND status='stored')
   OR NOT EXISTS(SELECT 1 FROM public.vitalia_account_roles WHERE account_id=NEW.patient_id AND role_code='paciente' AND active)
   THEN RAISE EXCEPTION 'Documento o paciente no disponible'; END IF;
  responsible:=public.vitalia_assert_care_selection(NEW.responsible_membership_id,NEW.specialty_id,NEW.branch_id);
  IF NOT EXISTS(SELECT 1 FROM public.vitalia_specialties WHERE id=NEW.specialty_id AND active)
   OR (NEW.branch_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.vitalia_branches WHERE id=NEW.branch_id AND active))
   THEN RAISE EXCEPTION 'Especialidad o sede no disponible'; END IF;
  IF NEW.previous_care_id IS NOT NULL THEN
   SELECT * INTO previous FROM public.vitalia_exam_care WHERE id=NEW.previous_care_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Atención previa no disponible'; END IF;
   IF NEW.kind='referral' THEN
    IF previous.status<>'referred' OR previous.clinic_id<>NEW.clinic_id OR previous.responsible_membership_id=NEW.responsible_membership_id
     OR NEW.requested_by<>public.vitalia_assert_care_professional(previous.responsible_membership_id)
     THEN RAISE EXCEPTION 'Derivación inválida'; END IF;
   ELSIF NEW.kind='second_opinion' AND previous.status<>'completed' THEN RAISE EXCEPTION 'Segunda opinión requiere atención completada';
   ELSIF NEW.kind='reselection' AND previous.status<>'cancelled' THEN RAISE EXCEPTION 'La nueva elección requiere cancelar la atención anterior'; END IF;
   IF NEW.prior_review_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.vitalia_care_reviews WHERE id=NEW.prior_review_id AND care_id=NEW.previous_care_id)
    THEN RAISE EXCEPTION 'Revisión previa no corresponde'; END IF;
  END IF;
  IF NEW.kind<>'referral' AND NEW.requested_by<>NEW.patient_id THEN RAISE EXCEPTION 'La elección corresponde al paciente'; END IF;
 ELSE
  IF (to_jsonb(NEW)-ARRAY['status','updated_by','revision','updated_at','closed_at']) IS DISTINCT FROM
     (to_jsonb(OLD)-ARRAY['status','updated_by','revision','updated_at','closed_at'])
   THEN RAISE EXCEPTION 'La identidad y el responsable de la atención son inmutables'; END IF;
  IF NEW.revision<>OLD.revision+1 OR NOT ((OLD.status='requested' AND NEW.status IN ('active','cancelled','referred'))
      OR (OLD.status='active' AND NEW.status IN ('completed','cancelled','referred')))
   THEN RAISE EXCEPTION 'Transición de atención inválida'; END IF;
  IF NOT (NEW.status='cancelled' AND NEW.updated_by=NEW.patient_id) THEN
   responsible:=public.vitalia_assert_care_selection(NEW.responsible_membership_id,NEW.specialty_id,NEW.branch_id);
   IF NEW.updated_by<>responsible THEN RAISE EXCEPTION 'Solo el responsable puede actualizar la atención'; END IF;
  END IF;
  IF NEW.status='completed' AND NOT EXISTS(SELECT 1 FROM public.vitalia_care_reviews WHERE care_id=NEW.id) THEN RAISE EXCEPTION 'Falta revisión profesional'; END IF;
  NEW.updated_at:=CURRENT_TIMESTAMP;
  NEW.closed_at:=CASE WHEN NEW.status IN ('completed','cancelled','referred') THEN CURRENT_TIMESTAMP ELSE NULL END;
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER vitalia_exam_care_guard BEFORE INSERT OR UPDATE OR DELETE ON public.vitalia_exam_care FOR EACH ROW EXECUTE FUNCTION public.vitalia_guard_exam_care();
CREATE FUNCTION public.vitalia_guard_care_review() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE care public.vitalia_exam_care; original jsonb;
BEGIN
 IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'La revisión aprobada es inmutable'; END IF;
 SELECT * INTO care FROM public.vitalia_exam_care WHERE id=NEW.care_id FOR UPDATE;
 IF NOT FOUND OR care.status<>'active' THEN RAISE EXCEPTION 'Atención no activa'; END IF;
 IF NEW.reviewer_id<>public.vitalia_assert_care_selection(care.responsible_membership_id,care.specialty_id,care.branch_id) THEN RAISE EXCEPTION 'Autor de revisión inválido'; END IF;
 SELECT result#>'{ai,extraction}' INTO original FROM public.vitalia_document_processing WHERE id=NEW.processing_id AND document_id=NEW.document_id AND status='requires_review';
 IF original IS NULL OR original IS DISTINCT FROM NEW.original_extraction THEN RAISE EXCEPTION 'La extracción original no corresponde'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER vitalia_care_review_guard BEFORE INSERT OR UPDATE OR DELETE ON public.vitalia_care_reviews FOR EACH ROW EXECUTE FUNCTION public.vitalia_guard_care_review();
CREATE FUNCTION public.vitalia_guard_referral() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'La derivación conserva su trazabilidad'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vitalia_exam_care s JOIN public.vitalia_exam_care t ON t.previous_care_id=s.id
 WHERE s.id=NEW.source_care_id AND t.id=NEW.target_care_id AND s.status='referred' AND t.kind='referral' AND t.requested_by=NEW.actor_id)
 THEN RAISE EXCEPTION 'Origen y destino de derivación incoherentes'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER vitalia_exam_referral_guard BEFORE INSERT OR UPDATE OR DELETE ON public.vitalia_exam_referrals FOR EACH ROW EXECUTE FUNCTION public.vitalia_guard_referral();
CREATE FUNCTION public.vitalia_audit_exam_care() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_TABLE_NAME='vitalia_exam_care' THEN
  INSERT INTO public.vitalia_care_audit(care_id,actor_id,action,details) VALUES(NEW.id,NEW.updated_by,NEW.status,jsonb_build_object('revision',NEW.revision,'kind',NEW.kind));
 ELSIF TG_TABLE_NAME='vitalia_care_reviews' THEN
  INSERT INTO public.vitalia_care_audit(care_id,actor_id,action,details) VALUES(NEW.care_id,NEW.reviewer_id,'review_approved',jsonb_build_object('reviewId',NEW.id));
 ELSE
  INSERT INTO public.vitalia_care_audit(care_id,actor_id,action,details) VALUES(NEW.source_care_id,NEW.actor_id,'referral_created',jsonb_build_object('referralId',NEW.id,'targetCareId',NEW.target_care_id));
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER vitalia_exam_care_audit AFTER INSERT OR UPDATE ON public.vitalia_exam_care FOR EACH ROW EXECUTE FUNCTION public.vitalia_audit_exam_care();
CREATE TRIGGER vitalia_care_review_audit AFTER INSERT ON public.vitalia_care_reviews FOR EACH ROW EXECUTE FUNCTION public.vitalia_audit_exam_care();
CREATE TRIGGER vitalia_exam_referral_audit AFTER INSERT ON public.vitalia_exam_referrals FOR EACH ROW EXECUTE FUNCTION public.vitalia_audit_exam_care();
CREATE TRIGGER vitalia_care_audit_immutable BEFORE UPDATE OR DELETE ON public.vitalia_care_audit FOR EACH ROW EXECUTE FUNCTION public.vitalia_prevent_membership_audit_change();

-- Origen y destino de una derivación deben quedar vinculados en la misma transacción.
CREATE FUNCTION public.vitalia_check_referral_pair() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.vitalia_exam_care c WHERE c.id=NEW.id AND
   ((c.status='referred' AND NOT EXISTS(SELECT 1 FROM public.vitalia_exam_referrals r WHERE r.source_care_id=c.id))
    OR (c.kind='referral' AND NOT EXISTS(SELECT 1 FROM public.vitalia_exam_referrals r WHERE r.target_care_id=c.id))))
 THEN RAISE EXCEPTION 'La derivación requiere origen, destino y vínculo atómicos'; END IF;
 RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER vitalia_care_referral_pair AFTER INSERT OR UPDATE ON public.vitalia_exam_care
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.vitalia_check_referral_pair();
REVOKE ALL ON public.vitalia_exam_care,public.vitalia_care_reviews,public.vitalia_exam_referrals,public.vitalia_care_audit FROM PUBLIC;
-- Sin permisos de API nuevos: la integración clínica requiere autorización por documento.
