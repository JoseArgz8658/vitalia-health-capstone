-- SIL Simple: primer circuito del laboratorio ficticio.
-- No cambia documentos ni procesamiento IA existentes.
CREATE TABLE public.vitalia_sil_orders (
 id uuid PRIMARY KEY,
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 created_by uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 exam_code text NOT NULL CHECK (exam_code = 'hemograma'),
 status text NOT NULL DEFAULT 'registered'
   CHECK (status IN ('registered','sampled','results_recorded')),
 synthetic boolean NOT NULL DEFAULT true CHECK (synthetic),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_sil_orders_patient_idx
 ON public.vitalia_sil_orders(patient_id,created_at DESC);

CREATE TABLE public.vitalia_sil_samples (
 id uuid PRIMARY KEY,
 order_id uuid NOT NULL UNIQUE REFERENCES public.vitalia_sil_orders(id),
 barcode text NOT NULL UNIQUE CHECK (length(barcode) BETWEEN 3 AND 40),
 sample_type text NOT NULL DEFAULT 'sangre_venosa'
   CHECK (sample_type = 'sangre_venosa'),
 registered_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE public.vitalia_sil_results (
 id uuid PRIMARY KEY,
 order_id uuid NOT NULL REFERENCES public.vitalia_sil_orders(id),
 analyte text NOT NULL CHECK (length(btrim(analyte)) BETWEEN 1 AND 100),
 numeric_value numeric(14,4) NOT NULL,
 unit text NOT NULL CHECK (length(btrim(unit)) BETWEEN 1 AND 30),
 reference_min numeric(14,4),
 reference_max numeric(14,4),
 synthetic boolean NOT NULL DEFAULT true CHECK (synthetic),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(order_id,analyte),
 CONSTRAINT vitalia_sil_ref_range CHECK (
   reference_min IS NULL OR reference_max IS NULL OR reference_min <= reference_max
 )
);
CREATE INDEX vitalia_sil_results_order_idx ON public.vitalia_sil_results(order_id);
