CREATE TABLE public.vitalia_exam_assistant_threads (
 id uuid PRIMARY KEY,
 review_id uuid NOT NULL UNIQUE REFERENCES public.vitalia_professional_reviews(id),
 document_id uuid NOT NULL REFERENCES public.vitalia_documents(id),
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 review_snapshot jsonb NOT NULL CHECK(jsonb_typeof(review_snapshot)='object'),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE public.vitalia_exam_assistant_turns (
 id uuid PRIMARY KEY,
 thread_id uuid NOT NULL REFERENCES public.vitalia_exam_assistant_threads(id),
 ordinal bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
 mode text NOT NULL CHECK(mode IN ('chat','explanation')),
 question text NOT NULL CHECK(length(question) BETWEEN 1 AND 500),
 status text NOT NULL CHECK(status IN ('pending','ready','failed')),
 attempt_id uuid NOT NULL,
 response jsonb,
 model text,
 prompt_version integer,
 elapsed_ms integer,
 approved boolean NOT NULL DEFAULT false CHECK(approved=false),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 started_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 finished_at timestamptz,
 CHECK((status='ready' AND response IS NOT NULL AND jsonb_typeof(response)='object' AND model IS NOT NULL AND prompt_version IS NOT NULL AND prompt_version=2 AND elapsed_ms IS NOT NULL AND elapsed_ms>=0 AND finished_at IS NOT NULL)
  OR (status='pending' AND response IS NULL AND finished_at IS NULL)
  OR (status='failed' AND response IS NULL AND finished_at IS NOT NULL))
);
CREATE UNIQUE INDEX vitalia_assistant_one_pending ON public.vitalia_exam_assistant_turns(thread_id) WHERE status='pending';
CREATE UNIQUE INDEX vitalia_assistant_one_explanation ON public.vitalia_exam_assistant_turns(thread_id) WHERE mode='explanation';
CREATE INDEX vitalia_assistant_thread_order ON public.vitalia_exam_assistant_turns(thread_id,ordinal);
CREATE TABLE public.vitalia_exam_assistant_audit (
 id uuid PRIMARY KEY,
 patient_id uuid NOT NULL REFERENCES public.vitalia_accounts(id),
 document_id uuid NOT NULL REFERENCES public.vitalia_documents(id),
 action text NOT NULL CHECK(action IN ('view','request','ready','failed')),
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
