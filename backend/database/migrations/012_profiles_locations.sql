-- Fase 7.1: estructura aditiva. No completa perfiles ni carga catálogos territoriales.
CREATE TABLE public.vitalia_regions (
 code text PRIMARY KEY CHECK (code = btrim(code) AND length(code) BETWEEN 1 AND 16),
 name text NOT NULL CHECK (length(btrim(name)) > 0)
);
CREATE TABLE public.vitalia_provinces (
 code text PRIMARY KEY CHECK (code = btrim(code) AND length(code) BETWEEN 1 AND 16),
 region_code text NOT NULL REFERENCES public.vitalia_regions(code),
 name text NOT NULL CHECK (length(btrim(name)) > 0)
);
CREATE INDEX vitalia_provinces_region ON public.vitalia_provinces(region_code);
CREATE TABLE public.vitalia_communes (
 code text PRIMARY KEY CHECK (code = btrim(code) AND length(code) BETWEEN 1 AND 16),
 province_code text NOT NULL REFERENCES public.vitalia_provinces(code),
 name text NOT NULL CHECK (length(btrim(name)) > 0)
);
CREATE INDEX vitalia_communes_province ON public.vitalia_communes(province_code);

CREATE TABLE public.vitalia_people (
 id uuid PRIMARY KEY,
 account_id uuid NOT NULL UNIQUE REFERENCES public.vitalia_accounts(id),
 first_name text NOT NULL CHECK (length(btrim(first_name)) > 0),
 additional_names text CHECK (additional_names IS NULL OR length(btrim(additional_names)) > 0),
 first_surname text NOT NULL CHECK (length(btrim(first_surname)) > 0),
 second_surname text CHECK (second_surname IS NULL OR length(btrim(second_surname)) > 0),
 birth_date date CHECK (birth_date IS NULL OR (isfinite(birth_date) AND birth_date <= CURRENT_DATE)),
 phone text CHECK (phone IS NULL OR length(btrim(phone)) > 0),
 preferred_commune_code text REFERENCES public.vitalia_communes(code),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK (updated_at >= created_at)
);
CREATE INDEX vitalia_people_commune ON public.vitalia_people(preferred_commune_code);
CREATE TABLE public.vitalia_person_identifiers (
 id uuid PRIMARY KEY,
 person_id uuid NOT NULL REFERENCES public.vitalia_people(id),
 country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
 identifier_type text NOT NULL CHECK (identifier_type ~ '^[A-Z][A-Z0-9_]{0,29}$'),
 normalized_value text NOT NULL CHECK (normalized_value = btrim(normalized_value) AND length(normalized_value) > 0),
 verification_status text NOT NULL DEFAULT 'not_verified' CHECK (verification_status IN ('not_verified','verified')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE (country_code,identifier_type,normalized_value),
 UNIQUE (person_id,country_code,identifier_type)
);
CREATE TABLE public.vitalia_patient_profiles (
 person_id uuid PRIMARY KEY REFERENCES public.vitalia_people(id),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE public.vitalia_professional_profiles (
 person_id uuid PRIMARY KEY REFERENCES public.vitalia_people(id),
 registration_reference text CHECK (registration_reference IS NULL OR length(btrim(registration_reference)) > 0),
 verification_status text NOT NULL DEFAULT 'pending' CHECK (verification_status IN ('pending','verified','rejected')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK (updated_at >= created_at)
);
CREATE TABLE public.vitalia_patient_measurements (
 id uuid PRIMARY KEY,
 patient_person_id uuid NOT NULL REFERENCES public.vitalia_patient_profiles(person_id),
 measured_at timestamptz NOT NULL CHECK (isfinite(measured_at) AND measured_at <= CURRENT_TIMESTAMP),
 weight_kg numeric CHECK (weight_kg IS NULL OR (weight_kg > 0 AND weight_kg < 'Infinity'::numeric)),
 height_cm numeric CHECK (height_cm IS NULL OR (height_cm > 0 AND height_cm < 'Infinity'::numeric)),
 source text NOT NULL CHECK (source IN ('patient_reported','professional_recorded')),
 recorded_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK (weight_kg IS NOT NULL OR height_cm IS NOT NULL)
);
CREATE INDEX vitalia_patient_measurements_history ON public.vitalia_patient_measurements(patient_person_id,measured_at DESC,id);
