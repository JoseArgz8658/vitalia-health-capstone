-- Laboratorio: roles operativos y catálogo versionado para demostración.
-- Evolución compatible con las órdenes de hemograma de la migración 026.
ALTER TABLE public.vitalia_roles DROP CONSTRAINT vitalia_roles_code_check;
ALTER TABLE public.vitalia_roles ADD CONSTRAINT vitalia_roles_code_check
  CHECK (code IN ('paciente','profesional','administrador',
                 'operador_laboratorio','validador_laboratorio'));
INSERT INTO public.vitalia_roles(code)
VALUES ('operador_laboratorio'),('validador_laboratorio');

CREATE TABLE public.vitalia_sil_exam_catalog (
  code text PRIMARY KEY CHECK (code ~ '^[a-z0-9_]{3,40}$'),
  name text NOT NULL UNIQUE,
  sample_type text NOT NULL DEFAULT 'sangre_venosa'
    CHECK (sample_type IN ('sangre_venosa')),
  active boolean NOT NULL DEFAULT true
);
INSERT INTO public.vitalia_sil_exam_catalog(code,name) VALUES
 ('hemograma','Hemograma'),
 ('perfil_lipidico','Perfil lipídico'),
 ('glicemia','Glicemia'),
 ('hba1c','Hemoglobina glicosilada (HbA1c)'),
 ('perfil_renal','Perfil renal'),
 ('perfil_hepatico','Perfil hepático');

-- Plantillas exclusivamente de demostración; sin intervalos clínicos universales.
CREATE TABLE public.vitalia_sil_exam_analytes (
  exam_code text NOT NULL REFERENCES public.vitalia_sil_exam_catalog(code),
  analyte text NOT NULL,
  unit text NOT NULL,
  demo_value numeric(14,4) NOT NULL,
  reference_min numeric(14,4),
  reference_max numeric(14,4),
  PRIMARY KEY(exam_code,analyte),
  CHECK(length(btrim(analyte)) BETWEEN 1 AND 100),
  CHECK(length(btrim(unit)) BETWEEN 1 AND 30),
  CHECK(reference_min IS NULL OR reference_max IS NULL OR reference_min <= reference_max)
);
INSERT INTO public.vitalia_sil_exam_analytes(exam_code,analyte,unit,demo_value,reference_min,reference_max) VALUES
 ('hemograma','Eritrocitos','10^6/uL',4.7,4.1,5.4),
 ('hemograma','Hematocrito','%',40,35,48),
 ('hemograma','Hemoglobina','g/dL',13.2,12,16),
 ('hemograma','Leucocitos','10^3/uL',7.2,4,11),
 ('hemograma','Plaquetas','10^3/uL',250,150,450),
 ('perfil_lipidico','Colesterol total','mg/dL',178,NULL,NULL),
 ('perfil_lipidico','Colesterol HDL','mg/dL',52,NULL,NULL),
 ('perfil_lipidico','Colesterol LDL','mg/dL',104,NULL,NULL),
 ('perfil_lipidico','Triglicéridos','mg/dL',110,NULL,NULL),
 ('glicemia','Glucosa','mg/dL',91,NULL,NULL),
 ('hba1c','HbA1c','%',5.4,NULL,NULL),
 ('perfil_renal','Creatinina','mg/dL',0.9,NULL,NULL),
 ('perfil_renal','Urea','mg/dL',28,NULL,NULL),
 ('perfil_renal','Nitrógeno ureico','mg/dL',13,NULL,NULL),
 ('perfil_hepatico','ALT','U/L',22,NULL,NULL),
 ('perfil_hepatico','AST','U/L',20,NULL,NULL),
 ('perfil_hepatico','GGT','U/L',18,NULL,NULL),
 ('perfil_hepatico','Fosfatasa alcalina','U/L',82,NULL,NULL),
 ('perfil_hepatico','Bilirrubina total','mg/dL',0.8,NULL,NULL);

-- Cada orden puede contener una o varias prestaciones del catálogo.
ALTER TABLE public.vitalia_sil_orders
  DROP CONSTRAINT vitalia_sil_orders_exam_code_check;
CREATE TABLE public.vitalia_sil_order_exams (
  order_id uuid NOT NULL REFERENCES public.vitalia_sil_orders(id),
  exam_code text NOT NULL REFERENCES public.vitalia_sil_exam_catalog(code),
  PRIMARY KEY(order_id,exam_code)
);
INSERT INTO public.vitalia_sil_order_exams(order_id,exam_code)
SELECT id,'hemograma' FROM public.vitalia_sil_orders;

-- Asociación explícita de cada analito a su prestación, evitando colisiones entre paneles.
ALTER TABLE public.vitalia_sil_results
  ADD COLUMN exam_code text NOT NULL DEFAULT 'hemograma';
ALTER TABLE public.vitalia_sil_results
  DROP CONSTRAINT vitalia_sil_results_order_id_analyte_key;
ALTER TABLE public.vitalia_sil_results
  ADD CONSTRAINT vitalia_sil_results_exam_analyte_unique
    UNIQUE(order_id,exam_code,analyte);
ALTER TABLE public.vitalia_sil_results
  ADD CONSTRAINT vitalia_sil_results_order_exam_fk
    FOREIGN KEY(order_id,exam_code)
    REFERENCES public.vitalia_sil_order_exams(order_id,exam_code);
