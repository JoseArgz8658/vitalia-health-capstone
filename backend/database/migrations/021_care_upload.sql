-- Contacto confirmado por examen. No completa domicilios ni atribuye atenciones históricas.
ALTER TABLE public.vitalia_people
 ADD COLUMN residence_commune_code text REFERENCES public.vitalia_communes(code),
 ADD COLUMN street text CHECK(street IS NULL OR length(btrim(street)) BETWEEN 1 AND 200),
 ADD COLUMN address_number text CHECK(address_number IS NULL OR length(btrim(address_number)) BETWEEN 1 AND 40);
ALTER TABLE public.vitalia_documents ADD COLUMN care_flow boolean NOT NULL DEFAULT false;
CREATE TABLE public.vitalia_care_contacts (
 care_id uuid PRIMARY KEY,
 document_id uuid NOT NULL UNIQUE,
 patient_id uuid NOT NULL,
 residence_commune_code text NOT NULL REFERENCES public.vitalia_communes(code),
 consultation_commune_code text NOT NULL REFERENCES public.vitalia_communes(code),
 street text NOT NULL CHECK(length(btrim(street)) BETWEEN 1 AND 200),
 address_number text NOT NULL CHECK(length(btrim(address_number)) BETWEEN 1 AND 40),
 phone text NOT NULL CHECK(phone ~ '^\+?[0-9]{8,15}$'),
 email text NOT NULL CHECK(length(email) BETWEEN 3 AND 254),
 confirmed boolean NOT NULL CHECK(confirmed),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY(care_id,document_id,patient_id) REFERENCES public.vitalia_exam_care(id,document_id,patient_id)
);
CREATE FUNCTION public.vitalia_guard_care_contact() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'El contacto confirmado conserva su trazabilidad'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vitalia_exam_care c JOIN public.vitalia_branches b ON b.id=c.branch_id
  JOIN public.vitalia_accounts a ON a.id=c.patient_id JOIN public.vitalia_documents d ON d.id=c.document_id
  WHERE c.id=NEW.care_id AND c.kind='initial' AND c.patient_id=NEW.patient_id AND d.care_flow
   AND b.commune_code=NEW.consultation_commune_code AND a.email=NEW.email)
 THEN RAISE EXCEPTION 'Contacto y elección no corresponden'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER vitalia_care_contact_guard BEFORE INSERT OR UPDATE OR DELETE ON public.vitalia_care_contacts
 FOR EACH ROW EXECUTE FUNCTION public.vitalia_guard_care_contact();
CREATE FUNCTION public.vitalia_check_care_upload() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.vitalia_documents d WHERE d.id=NEW.id AND d.status='stored' AND d.care_flow
  AND NOT EXISTS(SELECT 1 FROM public.vitalia_care_contacts c WHERE c.document_id=d.id AND c.patient_id=d.patient_id))
 THEN RAISE EXCEPTION 'Falta elección y contacto confirmados'; END IF;
 RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER vitalia_complete_care_upload AFTER INSERT OR UPDATE ON public.vitalia_documents
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.vitalia_check_care_upload();
REVOKE ALL ON public.vitalia_care_contacts FROM PUBLIC;
-- Bloqueo acotado sin conceder UPDATE sobre catálogos/asociaciones solo para leerlos.
CREATE FUNCTION public.vitalia_lock_care_selection(membership uuid,specialty uuid,branch uuid) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM 1 FROM public.vitalia_clinic_memberships m
 JOIN public.vitalia_people p ON p.id=m.professional_person_id
 JOIN public.vitalia_professional_profiles f ON f.person_id=p.id
 JOIN public.vitalia_account_roles g ON g.account_id=p.account_id AND g.role_code='profesional' AND g.active
 JOIN public.vitalia_clinics c ON c.id=m.clinic_id AND c.active
 JOIN public.vitalia_branch_memberships bm ON bm.membership_id=m.id AND bm.clinic_id=c.id
 JOIN public.vitalia_branches b ON b.id=bm.branch_id AND b.clinic_id=c.id AND b.active
 JOIN public.vitalia_membership_specialties ms ON ms.membership_id=m.id AND ms.clinic_id=c.id
 JOIN public.vitalia_specialties s ON s.id=ms.specialty_id AND s.active
 WHERE m.id=membership AND s.id=specialty AND b.id=branch AND m.active
 FOR SHARE OF m,f,g,c,bm,b,ms,s;
 IF NOT FOUND THEN RAISE EXCEPTION 'La selección ya no está disponible'; END IF;
 PERFORM public.vitalia_assert_care_selection(membership,specialty,branch);
END;
$$;
REVOKE ALL ON FUNCTION public.vitalia_lock_care_selection(uuid,uuid,uuid) FROM PUBLIC;
CREATE FUNCTION public.vitalia_prevent_care_downgrade() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.care_flow AND NOT NEW.care_flow THEN RAISE EXCEPTION 'El examen conserva su circuito de atención'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER vitalia_care_flow_guard BEFORE UPDATE ON public.vitalia_documents
 FOR EACH ROW EXECUTE FUNCTION public.vitalia_prevent_care_downgrade();
