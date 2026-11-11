# Diccionario del esquema implementado

Fuente: inventario de `vitalia_dev`, capturado 2026-10-08T01:30:32.670094-03:00.

Este documento describe las restricciones declaradas en PostgreSQL, no las reglas adicionales del backend. Contiene las 17 tablas del esquema public. No incluye datos de pacientes.

## vitalia_accounts

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| email | text | No | UNIQUE | Sin DEFAULT |
| password_hash | text | No | — | Sin DEFAULT |
| role_code | text | No | FK → vitalia_roles (code) | 'paciente'::text |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_accounts_email_key`: `UNIQUE (email)`
- `vitalia_accounts_email_normalized`: `CHECK (email = lower(btrim(email)) AND length(email) >= 3 AND length(email) <= 254)`
- `vitalia_accounts_password_hash_check`: `CHECK (length(password_hash) > 0)`
- `vitalia_accounts_pkey`: `PRIMARY KEY (id)`
- `vitalia_accounts_role_code_fkey`: `FOREIGN KEY (role_code) REFERENCES vitalia_roles(code)`

### Índices

- `CREATE UNIQUE INDEX vitalia_accounts_pkey ON public.vitalia_accounts USING btree (id)`
- `CREATE UNIQUE INDEX vitalia_accounts_email_key ON public.vitalia_accounts USING btree (email)`

## vitalia_assignment_audit

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| assignment_id | uuid | No | FK → vitalia_patient_assignments (id) | Sin DEFAULT |
| actor_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| action | text | No | — | Sin DEFAULT |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_assignment_audit_action_check`: `CHECK (action = ANY (ARRAY['activate'::text, 'deactivate'::text]))`
- `vitalia_assignment_audit_actor_id_fkey`: `FOREIGN KEY (actor_id) REFERENCES vitalia_accounts(id)`
- `vitalia_assignment_audit_assignment_id_fkey`: `FOREIGN KEY (assignment_id) REFERENCES vitalia_patient_assignments(id)`
- `vitalia_assignment_audit_pkey`: `PRIMARY KEY (id)`

### Índices

- `CREATE UNIQUE INDEX vitalia_assignment_audit_pkey ON public.vitalia_assignment_audit USING btree (id)`

## vitalia_document_audit

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | bigint | No | PK | Sin DEFAULT; IDENTITY ALWAYS |
| account_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| document_id | uuid | Sí | FK → vitalia_documents (id) | Sin DEFAULT |
| action | text | No | — | Sin DEFAULT |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_document_audit_account_id_fkey`: `FOREIGN KEY (account_id) REFERENCES vitalia_accounts(id)`
- `vitalia_document_audit_action_check`: `CHECK (action = ANY (ARRAY['upload'::text, 'list'::text, 'download'::text]))`
- `vitalia_document_audit_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES vitalia_documents(id)`
- `vitalia_document_audit_pkey`: `PRIMARY KEY (id)`

### Índices

- `CREATE UNIQUE INDEX vitalia_document_audit_pkey ON public.vitalia_document_audit USING btree (id)`
- `CREATE INDEX vitalia_document_audit_account_date ON public.vitalia_document_audit USING btree (account_id, created_at DESC)`

## vitalia_document_cleanup

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| document_id | uuid | No | FK → vitalia_documents (id); PK | Sin DEFAULT |
| cleaned_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_document_cleanup_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES vitalia_documents(id)`
- `vitalia_document_cleanup_pkey`: `PRIMARY KEY (document_id)`

### Índices

- `CREATE UNIQUE INDEX vitalia_document_cleanup_pkey ON public.vitalia_document_cleanup USING btree (document_id)`

## vitalia_document_processing

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| document_id | uuid | No | FK → vitalia_documents (id); UNIQUE | Sin DEFAULT |
| status | text | No | — | 'queued'::text |
| model | text | No | — | Sin DEFAULT |
| prompt_version | integer | No | — | Sin DEFAULT |
| result | jsonb | Sí | — | Sin DEFAULT |
| failure_code | text | Sí | — | Sin DEFAULT |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |
| started_at | timestamp with time zone | Sí | — | Sin DEFAULT |
| finished_at | timestamp with time zone | Sí | — | Sin DEFAULT |

### Restricciones declaradas

- `vitalia_document_processing_check`: `CHECK (status = 'queued'::text AND started_at IS NULL AND finished_at IS NULL AND result IS NULL AND failure_code IS NULL OR status = 'processing'::text AND started_at IS NOT NULL AND finished_at IS NULL AND result IS NULL AND failure_code IS NULL OR (status = ANY (ARRAY['requires_review'::text, 'rejected'::text])) AND started_at IS NOT NULL AND finished_at IS NOT NULL AND result IS NOT NULL AND failure_code IS NULL OR status = 'failed'::text AND started_at IS NOT NULL AND finished_at IS NOT NULL AND (result IS NOT NULL AND failure_code IS NULL OR result IS NULL AND failure_code IS NOT NULL))`
- `vitalia_document_processing_check1`: `CHECK (result IS NULL OR jsonb_typeof(result) = 'object'::text AND ((result -> 'approved'::text) = 'false'::jsonb) IS TRUE AND ((result ->> 'status'::text) =
CASE
    WHEN status = 'failed'::text THEN 'service_error'::text
    ELSE status
END) IS TRUE)`
- `vitalia_document_processing_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES vitalia_documents(id)`
- `vitalia_document_processing_document_id_key`: `UNIQUE (document_id)`
- `vitalia_document_processing_failure_code_check`: `CHECK (failure_code = ANY (ARRAY['processing_interrupted'::text, 'processing_failed'::text]))`
- `vitalia_document_processing_model_check`: `CHECK (length(model) >= 1 AND length(model) <= 100)`
- `vitalia_document_processing_pkey`: `PRIMARY KEY (id)`
- `vitalia_document_processing_prompt_version_check`: `CHECK (prompt_version > 0)`
- `vitalia_document_processing_status_check`: `CHECK (status = ANY (ARRAY['queued'::text, 'processing'::text, 'requires_review'::text, 'rejected'::text, 'failed'::text]))`

### Índices

- `CREATE UNIQUE INDEX vitalia_document_processing_pkey ON public.vitalia_document_processing USING btree (id)`
- `CREATE UNIQUE INDEX vitalia_document_processing_document_id_key ON public.vitalia_document_processing USING btree (document_id)`
- `CREATE INDEX vitalia_processing_pending ON public.vitalia_document_processing USING btree (created_at, id) WHERE (status = 'queued'::text)`

## vitalia_documents

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| patient_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| exam_name | text | No | — | Sin DEFAULT |
| exam_type | text | No | — | Sin DEFAULT |
| exam_date | date | No | — | Sin DEFAULT |
| original_name | text | No | — | Sin DEFAULT |
| content_type | text | No | — | Sin DEFAULT |
| size_bytes | integer | No | — | Sin DEFAULT |
| storage_key | text | No | UNIQUE | Sin DEFAULT |
| status | text | No | — | 'pending'::text |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_documents_content_type_check`: `CHECK (content_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text]))`
- `vitalia_documents_exam_name_check`: `CHECK (length(btrim(exam_name)) >= 1 AND length(btrim(exam_name)) <= 100)`
- `vitalia_documents_exam_type_check`: `CHECK (exam_type = ANY (ARRAY['Laboratorio'::text, 'Imagenología'::text]))`
- `vitalia_documents_original_name_check`: `CHECK (length(original_name) >= 1 AND length(original_name) <= 255)`
- `vitalia_documents_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES vitalia_accounts(id)`
- `vitalia_documents_pkey`: `PRIMARY KEY (id)`
- `vitalia_documents_size_bytes_check`: `CHECK (size_bytes >= 1 AND size_bytes <= 10485760)`
- `vitalia_documents_status_check`: `CHECK (status = ANY (ARRAY['pending'::text, 'stored'::text, 'failed'::text]))`
- `vitalia_documents_storage_key_key`: `UNIQUE (storage_key)`

### Índices

- `CREATE UNIQUE INDEX vitalia_documents_pkey ON public.vitalia_documents USING btree (id)`
- `CREATE UNIQUE INDEX vitalia_documents_storage_key_key ON public.vitalia_documents USING btree (storage_key)`
- `CREATE INDEX vitalia_documents_patient_history ON public.vitalia_documents USING btree (patient_id, exam_date DESC, created_at DESC)`

## vitalia_exam_assistant_audit

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| patient_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| document_id | uuid | No | FK → vitalia_documents (id) | Sin DEFAULT |
| action | text | No | — | Sin DEFAULT |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_exam_assistant_audit_action_check`: `CHECK (action = ANY (ARRAY['view'::text, 'request'::text, 'ready'::text, 'failed'::text]))`
- `vitalia_exam_assistant_audit_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES vitalia_documents(id)`
- `vitalia_exam_assistant_audit_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES vitalia_accounts(id)`
- `vitalia_exam_assistant_audit_pkey`: `PRIMARY KEY (id)`

### Índices

- `CREATE UNIQUE INDEX vitalia_exam_assistant_audit_pkey ON public.vitalia_exam_assistant_audit USING btree (id)`

## vitalia_exam_assistant_threads

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| review_id | uuid | No | FK → vitalia_professional_reviews (id); UNIQUE | Sin DEFAULT |
| document_id | uuid | No | FK → vitalia_documents (id) | Sin DEFAULT |
| patient_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| review_snapshot | jsonb | No | — | Sin DEFAULT |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_exam_assistant_threads_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES vitalia_documents(id)`
- `vitalia_exam_assistant_threads_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES vitalia_accounts(id)`
- `vitalia_exam_assistant_threads_pkey`: `PRIMARY KEY (id)`
- `vitalia_exam_assistant_threads_review_id_fkey`: `FOREIGN KEY (review_id) REFERENCES vitalia_professional_reviews(id)`
- `vitalia_exam_assistant_threads_review_id_key`: `UNIQUE (review_id)`
- `vitalia_exam_assistant_threads_review_snapshot_check`: `CHECK (jsonb_typeof(review_snapshot) = 'object'::text)`

### Índices

- `CREATE UNIQUE INDEX vitalia_exam_assistant_threads_pkey ON public.vitalia_exam_assistant_threads USING btree (id)`
- `CREATE UNIQUE INDEX vitalia_exam_assistant_threads_review_id_key ON public.vitalia_exam_assistant_threads USING btree (review_id)`

## vitalia_exam_assistant_turns

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| thread_id | uuid | No | FK → vitalia_exam_assistant_threads (id) | Sin DEFAULT |
| ordinal | bigint | No | UNIQUE | Sin DEFAULT; IDENTITY ALWAYS |
| mode | text | No | — | Sin DEFAULT |
| question | text | No | — | Sin DEFAULT |
| status | text | No | — | Sin DEFAULT |
| attempt_id | uuid | No | — | Sin DEFAULT |
| response | jsonb | Sí | — | Sin DEFAULT |
| model | text | Sí | — | Sin DEFAULT |
| prompt_version | integer | Sí | — | Sin DEFAULT |
| elapsed_ms | integer | Sí | — | Sin DEFAULT |
| approved | boolean | No | — | false |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |
| started_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |
| finished_at | timestamp with time zone | Sí | — | Sin DEFAULT |

### Restricciones declaradas

- `vitalia_exam_assistant_turns_approved_check`: `CHECK (approved = false)`
- `vitalia_exam_assistant_turns_check`: `CHECK (status = 'ready'::text AND response IS NOT NULL AND jsonb_typeof(response) = 'object'::text AND model IS NOT NULL AND prompt_version IS NOT NULL AND prompt_version = 2 AND elapsed_ms IS NOT NULL AND elapsed_ms >= 0 AND finished_at IS NOT NULL OR status = 'pending'::text AND response IS NULL AND finished_at IS NULL OR status = 'failed'::text AND response IS NULL AND finished_at IS NOT NULL)`
- `vitalia_exam_assistant_turns_mode_check`: `CHECK (mode = ANY (ARRAY['chat'::text, 'explanation'::text]))`
- `vitalia_exam_assistant_turns_ordinal_key`: `UNIQUE (ordinal)`
- `vitalia_exam_assistant_turns_pkey`: `PRIMARY KEY (id)`
- `vitalia_exam_assistant_turns_question_check`: `CHECK (length(question) >= 1 AND length(question) <= 500)`
- `vitalia_exam_assistant_turns_status_check`: `CHECK (status = ANY (ARRAY['pending'::text, 'ready'::text, 'failed'::text]))`
- `vitalia_exam_assistant_turns_thread_id_fkey`: `FOREIGN KEY (thread_id) REFERENCES vitalia_exam_assistant_threads(id)`

### Índices

- `CREATE UNIQUE INDEX vitalia_exam_assistant_turns_pkey ON public.vitalia_exam_assistant_turns USING btree (id)`
- `CREATE UNIQUE INDEX vitalia_exam_assistant_turns_ordinal_key ON public.vitalia_exam_assistant_turns USING btree (ordinal)`
- `CREATE UNIQUE INDEX vitalia_assistant_one_pending ON public.vitalia_exam_assistant_turns USING btree (thread_id) WHERE (status = 'pending'::text)`
- `CREATE UNIQUE INDEX vitalia_assistant_one_explanation ON public.vitalia_exam_assistant_turns USING btree (thread_id) WHERE (mode = 'explanation'::text)`
- `CREATE INDEX vitalia_assistant_thread_order ON public.vitalia_exam_assistant_turns USING btree (thread_id, ordinal)`

## vitalia_exam_explanations

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| review_id | uuid | No | FK → vitalia_professional_reviews (id); UNIQUE | Sin DEFAULT |
| document_id | uuid | No | FK → vitalia_documents (id) | Sin DEFAULT |
| patient_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| review_snapshot | jsonb | No | — | Sin DEFAULT |
| status | text | No | — | Sin DEFAULT |
| attempt_id | uuid | No | — | Sin DEFAULT |
| result | jsonb | Sí | — | Sin DEFAULT |
| model | text | Sí | — | Sin DEFAULT |
| prompt_version | integer | Sí | — | Sin DEFAULT |
| catalog_version | integer | Sí | — | Sin DEFAULT |
| elapsed_ms | integer | Sí | — | Sin DEFAULT |
| approved | boolean | No | — | false |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |
| started_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |
| finished_at | timestamp with time zone | Sí | — | Sin DEFAULT |

### Restricciones declaradas

- `vitalia_exam_explanations_approved_check`: `CHECK (approved = false)`
- `vitalia_exam_explanations_check`: `CHECK (status = 'ready'::text AND result IS NOT NULL AND jsonb_typeof(result) = 'object'::text AND model IS NOT NULL AND prompt_version IS NOT NULL AND catalog_version IS NOT NULL AND elapsed_ms IS NOT NULL AND elapsed_ms >= 0 AND finished_at IS NOT NULL OR status = 'generating'::text AND result IS NULL AND finished_at IS NULL OR status = 'failed'::text AND result IS NULL AND finished_at IS NOT NULL)`
- `vitalia_exam_explanations_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES vitalia_documents(id)`
- `vitalia_exam_explanations_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES vitalia_accounts(id)`
- `vitalia_exam_explanations_pkey`: `PRIMARY KEY (id)`
- `vitalia_exam_explanations_review_id_fkey`: `FOREIGN KEY (review_id) REFERENCES vitalia_professional_reviews(id)`
- `vitalia_exam_explanations_review_id_key`: `UNIQUE (review_id)`
- `vitalia_exam_explanations_review_snapshot_check`: `CHECK (jsonb_typeof(review_snapshot) = 'object'::text)`
- `vitalia_exam_explanations_status_check`: `CHECK (status = ANY (ARRAY['generating'::text, 'ready'::text, 'failed'::text]))`

### Índices

- `CREATE UNIQUE INDEX vitalia_exam_explanations_pkey ON public.vitalia_exam_explanations USING btree (id)`
- `CREATE UNIQUE INDEX vitalia_exam_explanations_review_id_key ON public.vitalia_exam_explanations USING btree (review_id)`
- `CREATE INDEX vitalia_exam_explanations_patient ON public.vitalia_exam_explanations USING btree (patient_id, created_at DESC)`

## vitalia_explanation_audit

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| patient_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| document_id | uuid | No | FK → vitalia_documents (id) | Sin DEFAULT |
| review_id | uuid | Sí | FK → vitalia_professional_reviews (id) | Sin DEFAULT |
| action | text | No | — | Sin DEFAULT |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_explanation_audit_action_check`: `CHECK (action = ANY (ARRAY['view'::text, 'request'::text, 'ready'::text, 'failed'::text]))`
- `vitalia_explanation_audit_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES vitalia_documents(id)`
- `vitalia_explanation_audit_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES vitalia_accounts(id)`
- `vitalia_explanation_audit_pkey`: `PRIMARY KEY (id)`
- `vitalia_explanation_audit_review_id_fkey`: `FOREIGN KEY (review_id) REFERENCES vitalia_professional_reviews(id)`

### Índices

- `CREATE UNIQUE INDEX vitalia_explanation_audit_pkey ON public.vitalia_explanation_audit USING btree (id)`
- `CREATE INDEX vitalia_explanation_audit_patient ON public.vitalia_explanation_audit USING btree (patient_id, created_at DESC)`

## vitalia_patient_assignments

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| professional_id | uuid | No | FK → vitalia_accounts (id); UNIQUE compuesto: professional_id, patient_id | Sin DEFAULT |
| patient_id | uuid | No | FK → vitalia_accounts (id); UNIQUE compuesto: professional_id, patient_id | Sin DEFAULT |
| active | boolean | No | — | true |
| created_by | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| updated_by | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |
| updated_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |
| deactivated_at | timestamp with time zone | Sí | — | Sin DEFAULT |

### Restricciones declaradas

- `vitalia_patient_assignments_check`: `CHECK (professional_id <> patient_id)`
- `vitalia_patient_assignments_check1`: `CHECK (active AND deactivated_at IS NULL OR NOT active AND deactivated_at IS NOT NULL)`
- `vitalia_patient_assignments_created_by_fkey`: `FOREIGN KEY (created_by) REFERENCES vitalia_accounts(id)`
- `vitalia_patient_assignments_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES vitalia_accounts(id)`
- `vitalia_patient_assignments_pkey`: `PRIMARY KEY (id)`
- `vitalia_patient_assignments_professional_id_fkey`: `FOREIGN KEY (professional_id) REFERENCES vitalia_accounts(id)`
- `vitalia_patient_assignments_professional_id_patient_id_key`: `UNIQUE (professional_id, patient_id)`
- `vitalia_patient_assignments_updated_by_fkey`: `FOREIGN KEY (updated_by) REFERENCES vitalia_accounts(id)`

### Índices

- `CREATE UNIQUE INDEX vitalia_patient_assignments_pkey ON public.vitalia_patient_assignments USING btree (id)`
- `CREATE UNIQUE INDEX vitalia_patient_assignments_professional_id_patient_id_key ON public.vitalia_patient_assignments USING btree (professional_id, patient_id)`
- `CREATE INDEX vitalia_patient_assignments_active_professional ON public.vitalia_patient_assignments USING btree (professional_id, patient_id) WHERE active`

## vitalia_professional_access_audit

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| professional_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| patient_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| assignment_id | uuid | No | FK → vitalia_patient_assignments (id) | Sin DEFAULT |
| document_id | uuid | Sí | FK → vitalia_documents (id) | Sin DEFAULT |
| processing_id | uuid | Sí | FK → vitalia_document_processing (id) | Sin DEFAULT |
| action | text | No | — | Sin DEFAULT |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_professional_access_audit_action_check`: `CHECK (action = ANY (ARRAY['list'::text, 'view_extraction'::text, 'download'::text]))`
- `vitalia_professional_access_audit_assignment_id_fkey`: `FOREIGN KEY (assignment_id) REFERENCES vitalia_patient_assignments(id)`
- `vitalia_professional_access_audit_check`: `CHECK (action = 'list'::text AND document_id IS NULL AND processing_id IS NULL OR action = 'download'::text AND document_id IS NOT NULL AND processing_id IS NULL OR action = 'view_extraction'::text AND document_id IS NOT NULL)`
- `vitalia_professional_access_audit_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES vitalia_documents(id)`
- `vitalia_professional_access_audit_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES vitalia_accounts(id)`
- `vitalia_professional_access_audit_pkey`: `PRIMARY KEY (id)`
- `vitalia_professional_access_audit_processing_id_fkey`: `FOREIGN KEY (processing_id) REFERENCES vitalia_document_processing(id)`
- `vitalia_professional_access_audit_professional_id_fkey`: `FOREIGN KEY (professional_id) REFERENCES vitalia_accounts(id)`

### Índices

- `CREATE UNIQUE INDEX vitalia_professional_access_audit_pkey ON public.vitalia_professional_access_audit USING btree (id)`
- `CREATE INDEX vitalia_professional_access_patient_date ON public.vitalia_professional_access_audit USING btree (patient_id, created_at DESC)`
- `CREATE INDEX vitalia_professional_access_actor_date ON public.vitalia_professional_access_audit USING btree (professional_id, created_at DESC)`

## vitalia_professional_reviews

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| id | uuid | No | PK | Sin DEFAULT |
| processing_id | uuid | No | FK → vitalia_document_processing (id); UNIQUE | Sin DEFAULT |
| document_id | uuid | No | FK → vitalia_documents (id) | Sin DEFAULT |
| patient_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| assignment_id | uuid | No | FK → vitalia_patient_assignments (id) | Sin DEFAULT |
| reviewer_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| original_extraction | jsonb | No | — | Sin DEFAULT |
| reviewed_extraction | jsonb | No | — | Sin DEFAULT |
| observations | text | No | — | Sin DEFAULT |
| confirmed_original | boolean | No | — | Sin DEFAULT |
| approved | boolean | No | — | true |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_professional_reviews_approved_check`: `CHECK (approved = true)`
- `vitalia_professional_reviews_assignment_id_fkey`: `FOREIGN KEY (assignment_id) REFERENCES vitalia_patient_assignments(id)`
- `vitalia_professional_reviews_confirmed_original_check`: `CHECK (confirmed_original = true)`
- `vitalia_professional_reviews_document_id_fkey`: `FOREIGN KEY (document_id) REFERENCES vitalia_documents(id)`
- `vitalia_professional_reviews_observations_check`: `CHECK (length(observations) <= 2000)`
- `vitalia_professional_reviews_original_extraction_check`: `CHECK (jsonb_typeof(original_extraction) = 'object'::text)`
- `vitalia_professional_reviews_patient_id_fkey`: `FOREIGN KEY (patient_id) REFERENCES vitalia_accounts(id)`
- `vitalia_professional_reviews_pkey`: `PRIMARY KEY (id)`
- `vitalia_professional_reviews_processing_id_fkey`: `FOREIGN KEY (processing_id) REFERENCES vitalia_document_processing(id)`
- `vitalia_professional_reviews_processing_id_key`: `UNIQUE (processing_id)`
- `vitalia_professional_reviews_reviewed_extraction_check`: `CHECK (jsonb_typeof(reviewed_extraction) = 'object'::text)`
- `vitalia_professional_reviews_reviewer_id_fkey`: `FOREIGN KEY (reviewer_id) REFERENCES vitalia_accounts(id)`

### Índices

- `CREATE UNIQUE INDEX vitalia_professional_reviews_pkey ON public.vitalia_professional_reviews USING btree (id)`
- `CREATE UNIQUE INDEX vitalia_professional_reviews_processing_id_key ON public.vitalia_professional_reviews USING btree (processing_id)`
- `CREATE INDEX vitalia_professional_reviews_patient_date ON public.vitalia_professional_reviews USING btree (patient_id, created_at DESC)`

## vitalia_roles

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| code | text | No | PK | Sin DEFAULT |

### Restricciones declaradas

- `vitalia_roles_code_check`: `CHECK (code = ANY (ARRAY['paciente'::text, 'profesional'::text, 'administrador'::text]))`
- `vitalia_roles_pkey`: `PRIMARY KEY (code)`

### Índices

- `CREATE UNIQUE INDEX vitalia_roles_pkey ON public.vitalia_roles USING btree (code)`

## vitalia_schema_migrations

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| version | text | No | PK | Sin DEFAULT |
| checksum | text | No | — | Sin DEFAULT |
| applied_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |

### Restricciones declaradas

- `vitalia_schema_migrations_pkey`: `PRIMARY KEY (version)`

### Índices

- `CREATE UNIQUE INDEX vitalia_schema_migrations_pkey ON public.vitalia_schema_migrations USING btree (version)`

## vitalia_sessions

| Atributo | Tipo PostgreSQL | Admite NULL | Clave / referencia | Predeterminado |
|---|---|---|---|---|
| token_hash | text | No | PK | Sin DEFAULT |
| account_id | uuid | No | FK → vitalia_accounts (id) | Sin DEFAULT |
| created_at | timestamp with time zone | No | — | CURRENT_TIMESTAMP |
| expires_at | timestamp with time zone | No | — | Sin DEFAULT |

### Restricciones declaradas

- `vitalia_sessions_account_id_fkey`: `FOREIGN KEY (account_id) REFERENCES vitalia_accounts(id)`
- `vitalia_sessions_expiry_check`: `CHECK (expires_at > created_at)`
- `vitalia_sessions_pkey`: `PRIMARY KEY (token_hash)`
- `vitalia_sessions_token_hash_check`: `CHECK (token_hash ~ '^[a-f0-9]{64}$'::text)`

### Índices

- `CREATE UNIQUE INDEX vitalia_sessions_pkey ON public.vitalia_sessions USING btree (token_hash)`
