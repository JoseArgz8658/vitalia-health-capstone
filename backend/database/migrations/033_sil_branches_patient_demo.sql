-- Datos ficticios exclusivamente para SIL demo. No habilitar para pacientes reales.
-- Catálogo normalizado laboratorio -> sucursal. No crea clínicas ni centros reales.
CREATE TABLE public.vitalia_sil_laboratories (
  code text PRIMARY KEY,
  display_name text NOT NULL CHECK(length(btrim(display_name)) BETWEEN 3 AND 120),
  synthetic boolean NOT NULL DEFAULT true CHECK(synthetic)
);
CREATE TABLE public.vitalia_sil_branches (
  code text PRIMARY KEY,
  laboratory_code text NOT NULL REFERENCES public.vitalia_sil_laboratories(code),
  display_name text NOT NULL CHECK(length(btrim(display_name)) BETWEEN 3 AND 100),
  commune text NOT NULL CHECK(length(btrim(commune)) BETWEEN 3 AND 80),
  active boolean NOT NULL DEFAULT true,
  synthetic boolean NOT NULL DEFAULT true CHECK(synthetic)
);
INSERT INTO public.vitalia_sil_laboratories(code,display_name)
 VALUES('perez-demo','Laboratorio Pérez (ficticio)');
INSERT INTO public.vitalia_sil_branches(code,laboratory_code,display_name,commune)
 VALUES
  ('perez-vitacura','perez-demo','Sucursal Vitacura','Vitacura'),
  ('perez-las-condes','perez-demo','Sucursal Las Condes','Las Condes'),
  ('perez-providencia','perez-demo','Sucursal Providencia','Providencia');

-- Datos demográficos SOLO ficticios para probar asociación manual contra el PDF.
-- Sin RUN reales: solo un identificador sintético DEMO-XXXXXXXX.
CREATE TABLE public.vitalia_sil_patient_profiles_demo (
  patient_id uuid PRIMARY KEY REFERENCES public.vitalia_accounts(id),
  synthetic_identifier text NOT NULL UNIQUE
    CHECK(synthetic_identifier ~ '^DEMO-[A-Z0-9-]{3,16}$'),
  given_names text NOT NULL CHECK(length(btrim(given_names)) BETWEEN 2 AND 100),
  family_names text NOT NULL CHECK(length(btrim(family_names)) BETWEEN 2 AND 100),
  birth_date date NOT NULL CHECK(birth_date BETWEEN DATE '1900-01-01' AND DATE '2100-01-01'),
  sex_for_reference text NOT NULL CHECK(sex_for_reference IN ('female','male','not_specified')),
  contact_phone_demo text CHECK(contact_phone_demo IS NULL OR
    length(contact_phone_demo) BETWEEN 6 AND 20),
  synthetic boolean NOT NULL DEFAULT true CHECK(synthetic),
  updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.vitalia_sil_orders
  ADD COLUMN origin_branch_code text REFERENCES public.vitalia_sil_branches(code);

ALTER TABLE public.vitalia_sil_external_reports
  ADD COLUMN origin_branch_code text REFERENCES public.vitalia_sil_branches(code),
  ADD COLUMN authorized_professional_name text
    CHECK(authorized_professional_name IS NULL OR
      length(btrim(authorized_professional_name)) BETWEEN 3 AND 120),
  ADD COLUMN patient_identifier_checked boolean NOT NULL DEFAULT false;

-- Los reportes existentes se preservan sin atribuir una verificación no realizada.
