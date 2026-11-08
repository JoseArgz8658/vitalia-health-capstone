-- Trazabilidad postanalítica de un laboratorio de pruebas aislado.
-- Mantener datos de órdenes y resultados preexistentes.
CREATE TABLE public.vitalia_sil_containers (
  code text PRIMARY KEY,
  label text NOT NULL,
  sample_type text NOT NULL DEFAULT 'sangre_venosa'
    CHECK(sample_type='sangre_venosa'),
  CHECK(code IN ('edta','serum','fluoride'))
);
INSERT INTO public.vitalia_sil_containers(code,label) VALUES
('edta','Tubo EDTA'),('serum','Tubo de suero'),('fluoride','Tubo con fluoruro');

CREATE TABLE public.vitalia_sil_exam_containers (
  exam_code text PRIMARY KEY REFERENCES public.vitalia_sil_exam_catalog(code),
  container_code text NOT NULL REFERENCES public.vitalia_sil_containers(code)
);
INSERT INTO public.vitalia_sil_exam_containers(exam_code,container_code) VALUES
('hemograma','edta'),('hba1c','edta'),
('perfil_lipidico','serum'),('perfil_renal','serum'),('perfil_hepatico','serum'),
('glicemia','fluoride');

-- Mantener las recepciones históricas, cuya clase de tubo no fue registrada.
ALTER TABLE public.vitalia_sil_samples DROP CONSTRAINT vitalia_sil_samples_order_id_key;
ALTER TABLE public.vitalia_sil_samples
  ADD COLUMN container_code text NOT NULL DEFAULT 'historical'
    CHECK(container_code IN ('historical','edta','serum','fluoride')),
  ADD COLUMN received_by uuid REFERENCES public.vitalia_accounts(id),
  ADD COLUMN receipt_note text CHECK(receipt_note IS NULL OR length(receipt_note)<=300),
  ADD CONSTRAINT vitalia_sil_samples_order_container_unique UNIQUE(order_id,container_code);

ALTER TABLE public.vitalia_sil_results
  ADD COLUMN entry_method text NOT NULL DEFAULT 'legacy'
    CHECK(entry_method IN ('legacy','simulated','manual'));

CREATE TABLE public.vitalia_sil_audit (
  id uuid PRIMARY KEY,
  order_id uuid NOT NULL REFERENCES public.vitalia_sil_orders(id),
  actor_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
  action text NOT NULL CHECK(action IN ('order_created','sample_received',
    'results_simulated','results_manual')),
  details jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK(jsonb_typeof(details)='object'),
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX vitalia_sil_audit_order_idx
  ON public.vitalia_sil_audit(order_id,created_at,id);
