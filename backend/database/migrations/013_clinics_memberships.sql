-- Fase 7.2: estructura institucional. No concede acceso clínico ni crea invitaciones.
CREATE TABLE public.vitalia_clinics (
 id uuid PRIMARY KEY,
 name text NOT NULL CHECK (name = btrim(name) AND length(name) BETWEEN 1 AND 150),
 active boolean NOT NULL DEFAULT true,
 contact_phone text CHECK (contact_phone IS NULL OR length(btrim(contact_phone)) BETWEEN 1 AND 40),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK (isfinite(created_at))
);
CREATE TABLE public.vitalia_branches (
 id uuid PRIMARY KEY,
 clinic_id uuid NOT NULL REFERENCES public.vitalia_clinics(id),
 commune_code text NOT NULL REFERENCES public.vitalia_communes(code),
 name text NOT NULL CHECK (name = btrim(name) AND length(name) BETWEEN 1 AND 150),
 street text NOT NULL CHECK (length(btrim(street)) BETWEEN 1 AND 200),
 address_number text NOT NULL CHECK (length(btrim(address_number)) BETWEEN 1 AND 40),
 floor text CHECK (floor IS NULL OR length(btrim(floor)) BETWEEN 1 AND 40),
 unit text CHECK (unit IS NULL OR length(btrim(unit)) BETWEEN 1 AND 40),
 contact_phone text CHECK (contact_phone IS NULL OR length(btrim(contact_phone)) BETWEEN 1 AND 40),
 active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK (isfinite(created_at)),
 UNIQUE (clinic_id,id)
);
CREATE INDEX vitalia_branches_commune ON public.vitalia_branches(commune_code);
CREATE TABLE public.vitalia_specialties (
 id uuid PRIMARY KEY,
 name text NOT NULL CHECK (name = btrim(name) AND length(name) BETWEEN 1 AND 150),
 active boolean NOT NULL DEFAULT true,
 UNIQUE (name)
);
CREATE UNIQUE INDEX vitalia_specialties_name_normalized ON public.vitalia_specialties(lower(name));
CREATE TABLE public.vitalia_professional_specialties (
 professional_person_id uuid NOT NULL REFERENCES public.vitalia_professional_profiles(person_id),
 specialty_id uuid NOT NULL REFERENCES public.vitalia_specialties(id),
 PRIMARY KEY (professional_person_id,specialty_id)
);
CREATE INDEX vitalia_professional_specialties_specialty ON public.vitalia_professional_specialties(specialty_id);
CREATE TABLE public.vitalia_clinic_memberships (
 id uuid PRIMARY KEY,
 clinic_id uuid NOT NULL REFERENCES public.vitalia_clinics(id),
 professional_person_id uuid NOT NULL REFERENCES public.vitalia_professional_profiles(person_id),
 clinical_role text NOT NULL DEFAULT 'profesional' CHECK (clinical_role IN ('profesional','jefe_clinico')),
 active boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK (isfinite(created_at)),
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK (isfinite(updated_at)),
 UNIQUE (clinic_id,professional_person_id),
 UNIQUE (clinic_id,id),
 CHECK (updated_at >= created_at)
);
CREATE INDEX vitalia_clinic_memberships_professional ON public.vitalia_clinic_memberships(professional_person_id);
CREATE TABLE public.vitalia_branch_memberships (
 clinic_id uuid NOT NULL,
 branch_id uuid NOT NULL,
 membership_id uuid NOT NULL,
 PRIMARY KEY (branch_id,membership_id),
 FOREIGN KEY (clinic_id,branch_id) REFERENCES public.vitalia_branches(clinic_id,id),
 FOREIGN KEY (clinic_id,membership_id) REFERENCES public.vitalia_clinic_memberships(clinic_id,id)
);
CREATE INDEX vitalia_branch_memberships_membership ON public.vitalia_branch_memberships(clinic_id,membership_id);
