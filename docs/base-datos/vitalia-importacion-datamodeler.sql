-- SOLO IMPORTACION VISUAL EN DATA MODELER. NO EJECUTAR EN VITALIA_DEV.
-- Adaptacion Oracle: no es una migracion ni una replica completa de PostgreSQL.
-- Mismos nombres, columnas, nulabilidad, PK, UNIQUE y FK que el inventario.
-- DEFAULT, IDENTITY, CHECK, indices y triggers NO se reproducen aqui.
-- Tipos originales y restricciones: diccionario-actual.md.

CREATE TABLE vitalia_accounts (
    id VARCHAR2(36) NOT NULL,
    email VARCHAR2(4000) NOT NULL,
    password_hash VARCHAR2(4000) NOT NULL,
    role_code VARCHAR2(4000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_assignment_audit (
    id VARCHAR2(36) NOT NULL,
    assignment_id VARCHAR2(36) NOT NULL,
    actor_id VARCHAR2(36) NOT NULL,
    action VARCHAR2(4000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_document_audit (
    id NUMBER(19) NOT NULL,
    account_id VARCHAR2(36) NOT NULL,
    document_id VARCHAR2(36),
    action VARCHAR2(4000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_document_cleanup (
    document_id VARCHAR2(36) NOT NULL,
    cleaned_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_document_processing (
    id VARCHAR2(36) NOT NULL,
    document_id VARCHAR2(36) NOT NULL,
    status VARCHAR2(4000) NOT NULL,
    model VARCHAR2(4000) NOT NULL,
    prompt_version NUMBER(10) NOT NULL,
    result CLOB,
    failure_code VARCHAR2(4000),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE,
    finished_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE vitalia_documents (
    id VARCHAR2(36) NOT NULL,
    patient_id VARCHAR2(36) NOT NULL,
    exam_name VARCHAR2(4000) NOT NULL,
    exam_type VARCHAR2(4000) NOT NULL,
    exam_date DATE NOT NULL,
    original_name VARCHAR2(4000) NOT NULL,
    content_type VARCHAR2(4000) NOT NULL,
    size_bytes NUMBER(10) NOT NULL,
    storage_key VARCHAR2(4000) NOT NULL,
    status VARCHAR2(4000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_exam_assistant_audit (
    id VARCHAR2(36) NOT NULL,
    patient_id VARCHAR2(36) NOT NULL,
    document_id VARCHAR2(36) NOT NULL,
    action VARCHAR2(4000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_exam_assistant_threads (
    id VARCHAR2(36) NOT NULL,
    review_id VARCHAR2(36) NOT NULL,
    document_id VARCHAR2(36) NOT NULL,
    patient_id VARCHAR2(36) NOT NULL,
    review_snapshot CLOB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_exam_assistant_turns (
    id VARCHAR2(36) NOT NULL,
    thread_id VARCHAR2(36) NOT NULL,
    ordinal NUMBER(19) NOT NULL,
    mode VARCHAR2(4000) NOT NULL,
    question VARCHAR2(4000) NOT NULL,
    status VARCHAR2(4000) NOT NULL,
    attempt_id VARCHAR2(36) NOT NULL,
    response CLOB,
    model VARCHAR2(4000),
    prompt_version NUMBER(10),
    elapsed_ms NUMBER(10),
    approved NUMBER(1) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    finished_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE vitalia_exam_explanations (
    id VARCHAR2(36) NOT NULL,
    review_id VARCHAR2(36) NOT NULL,
    document_id VARCHAR2(36) NOT NULL,
    patient_id VARCHAR2(36) NOT NULL,
    review_snapshot CLOB NOT NULL,
    status VARCHAR2(4000) NOT NULL,
    attempt_id VARCHAR2(36) NOT NULL,
    result CLOB,
    model VARCHAR2(4000),
    prompt_version NUMBER(10),
    catalog_version NUMBER(10),
    elapsed_ms NUMBER(10),
    approved NUMBER(1) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    finished_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE vitalia_explanation_audit (
    id VARCHAR2(36) NOT NULL,
    patient_id VARCHAR2(36) NOT NULL,
    document_id VARCHAR2(36) NOT NULL,
    review_id VARCHAR2(36),
    action VARCHAR2(4000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_patient_assignments (
    id VARCHAR2(36) NOT NULL,
    professional_id VARCHAR2(36) NOT NULL,
    patient_id VARCHAR2(36) NOT NULL,
    active NUMBER(1) NOT NULL,
    created_by VARCHAR2(36) NOT NULL,
    updated_by VARCHAR2(36) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    deactivated_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE vitalia_professional_access_audit (
    id VARCHAR2(36) NOT NULL,
    professional_id VARCHAR2(36) NOT NULL,
    patient_id VARCHAR2(36) NOT NULL,
    assignment_id VARCHAR2(36) NOT NULL,
    document_id VARCHAR2(36),
    processing_id VARCHAR2(36),
    action VARCHAR2(4000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_professional_reviews (
    id VARCHAR2(36) NOT NULL,
    processing_id VARCHAR2(36) NOT NULL,
    document_id VARCHAR2(36) NOT NULL,
    patient_id VARCHAR2(36) NOT NULL,
    assignment_id VARCHAR2(36) NOT NULL,
    reviewer_id VARCHAR2(36) NOT NULL,
    original_extraction CLOB NOT NULL,
    reviewed_extraction CLOB NOT NULL,
    observations VARCHAR2(4000) NOT NULL,
    confirmed_original NUMBER(1) NOT NULL,
    approved NUMBER(1) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_roles (
    code VARCHAR2(4000) NOT NULL
);

CREATE TABLE vitalia_schema_migrations (
    version VARCHAR2(4000) NOT NULL,
    checksum VARCHAR2(4000) NOT NULL,
    applied_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_sessions (
    token_hash VARCHAR2(4000) NOT NULL,
    account_id VARCHAR2(36) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE vitalia_accounts ADD CONSTRAINT vitalia_accounts_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_assignment_audit ADD CONSTRAINT vitalia_assignment_audit_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_document_audit ADD CONSTRAINT vitalia_document_audit_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_document_cleanup ADD CONSTRAINT vitalia_document_cleanup_pkey PRIMARY KEY (document_id);
ALTER TABLE vitalia_document_processing ADD CONSTRAINT vitalia_document_processing_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_documents ADD CONSTRAINT vitalia_documents_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_exam_assistant_audit ADD CONSTRAINT vitalia_exam_assistant_audit_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_exam_assistant_threads ADD CONSTRAINT vitalia_exam_assistant_threads_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_exam_assistant_turns ADD CONSTRAINT vitalia_exam_assistant_turns_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_exam_explanations ADD CONSTRAINT vitalia_exam_explanations_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_explanation_audit ADD CONSTRAINT vitalia_explanation_audit_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_patient_assignments ADD CONSTRAINT vitalia_patient_assignments_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_professional_access_audit ADD CONSTRAINT vitalia_professional_access_audit_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_professional_reviews ADD CONSTRAINT vitalia_professional_reviews_pkey PRIMARY KEY (id);
ALTER TABLE vitalia_roles ADD CONSTRAINT vitalia_roles_pkey PRIMARY KEY (code);
ALTER TABLE vitalia_schema_migrations ADD CONSTRAINT vitalia_schema_migrations_pkey PRIMARY KEY (version);
ALTER TABLE vitalia_sessions ADD CONSTRAINT vitalia_sessions_pkey PRIMARY KEY (token_hash);

ALTER TABLE vitalia_accounts ADD CONSTRAINT vitalia_accounts_email_key UNIQUE (email);
ALTER TABLE vitalia_document_processing ADD CONSTRAINT vitalia_document_processing_document_id_key UNIQUE (document_id);
ALTER TABLE vitalia_documents ADD CONSTRAINT vitalia_documents_storage_key_key UNIQUE (storage_key);
ALTER TABLE vitalia_exam_assistant_threads ADD CONSTRAINT vitalia_exam_assistant_threads_review_id_key UNIQUE (review_id);
ALTER TABLE vitalia_exam_assistant_turns ADD CONSTRAINT vitalia_exam_assistant_turns_ordinal_key UNIQUE (ordinal);
ALTER TABLE vitalia_exam_explanations ADD CONSTRAINT vitalia_exam_explanations_review_id_key UNIQUE (review_id);
ALTER TABLE vitalia_patient_assignments ADD CONSTRAINT vitalia_patient_assignments_professional_id_patient_id_key UNIQUE (professional_id, patient_id);
ALTER TABLE vitalia_professional_reviews ADD CONSTRAINT vitalia_professional_reviews_processing_id_key UNIQUE (processing_id);

ALTER TABLE vitalia_accounts ADD CONSTRAINT vitalia_accounts_role_code_fkey FOREIGN KEY (role_code) REFERENCES vitalia_roles (code);
ALTER TABLE vitalia_assignment_audit ADD CONSTRAINT vitalia_assignment_audit_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_assignment_audit ADD CONSTRAINT vitalia_assignment_audit_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES vitalia_patient_assignments (id);
ALTER TABLE vitalia_document_audit ADD CONSTRAINT vitalia_document_audit_account_id_fkey FOREIGN KEY (account_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_document_audit ADD CONSTRAINT vitalia_document_audit_document_id_fkey FOREIGN KEY (document_id) REFERENCES vitalia_documents (id);
ALTER TABLE vitalia_document_cleanup ADD CONSTRAINT vitalia_document_cleanup_document_id_fkey FOREIGN KEY (document_id) REFERENCES vitalia_documents (id);
ALTER TABLE vitalia_document_processing ADD CONSTRAINT vitalia_document_processing_document_id_fkey FOREIGN KEY (document_id) REFERENCES vitalia_documents (id);
ALTER TABLE vitalia_documents ADD CONSTRAINT vitalia_documents_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_exam_assistant_audit ADD CONSTRAINT vitalia_exam_assistant_audit_document_id_fkey FOREIGN KEY (document_id) REFERENCES vitalia_documents (id);
ALTER TABLE vitalia_exam_assistant_audit ADD CONSTRAINT vitalia_exam_assistant_audit_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_exam_assistant_threads ADD CONSTRAINT vitalia_exam_assistant_threads_document_id_fkey FOREIGN KEY (document_id) REFERENCES vitalia_documents (id);
ALTER TABLE vitalia_exam_assistant_threads ADD CONSTRAINT vitalia_exam_assistant_threads_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_exam_assistant_threads ADD CONSTRAINT vitalia_exam_assistant_threads_review_id_fkey FOREIGN KEY (review_id) REFERENCES vitalia_professional_reviews (id);
ALTER TABLE vitalia_exam_assistant_turns ADD CONSTRAINT vitalia_exam_assistant_turns_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES vitalia_exam_assistant_threads (id);
ALTER TABLE vitalia_exam_explanations ADD CONSTRAINT vitalia_exam_explanations_document_id_fkey FOREIGN KEY (document_id) REFERENCES vitalia_documents (id);
ALTER TABLE vitalia_exam_explanations ADD CONSTRAINT vitalia_exam_explanations_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_exam_explanations ADD CONSTRAINT vitalia_exam_explanations_review_id_fkey FOREIGN KEY (review_id) REFERENCES vitalia_professional_reviews (id);
ALTER TABLE vitalia_explanation_audit ADD CONSTRAINT vitalia_explanation_audit_document_id_fkey FOREIGN KEY (document_id) REFERENCES vitalia_documents (id);
ALTER TABLE vitalia_explanation_audit ADD CONSTRAINT vitalia_explanation_audit_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_explanation_audit ADD CONSTRAINT vitalia_explanation_audit_review_id_fkey FOREIGN KEY (review_id) REFERENCES vitalia_professional_reviews (id);
ALTER TABLE vitalia_patient_assignments ADD CONSTRAINT vitalia_patient_assignments_created_by_fkey FOREIGN KEY (created_by) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_patient_assignments ADD CONSTRAINT vitalia_patient_assignments_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_patient_assignments ADD CONSTRAINT vitalia_patient_assignments_professional_id_fkey FOREIGN KEY (professional_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_patient_assignments ADD CONSTRAINT vitalia_patient_assignments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_professional_access_audit ADD CONSTRAINT vitalia_professional_access_audit_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES vitalia_patient_assignments (id);
ALTER TABLE vitalia_professional_access_audit ADD CONSTRAINT vitalia_professional_access_audit_document_id_fkey FOREIGN KEY (document_id) REFERENCES vitalia_documents (id);
ALTER TABLE vitalia_professional_access_audit ADD CONSTRAINT vitalia_professional_access_audit_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_professional_access_audit ADD CONSTRAINT vitalia_professional_access_audit_processing_id_fkey FOREIGN KEY (processing_id) REFERENCES vitalia_document_processing (id);
ALTER TABLE vitalia_professional_access_audit ADD CONSTRAINT vitalia_professional_access_audit_professional_id_fkey FOREIGN KEY (professional_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_professional_reviews ADD CONSTRAINT vitalia_professional_reviews_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES vitalia_patient_assignments (id);
ALTER TABLE vitalia_professional_reviews ADD CONSTRAINT vitalia_professional_reviews_document_id_fkey FOREIGN KEY (document_id) REFERENCES vitalia_documents (id);
ALTER TABLE vitalia_professional_reviews ADD CONSTRAINT vitalia_professional_reviews_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_professional_reviews ADD CONSTRAINT vitalia_professional_reviews_processing_id_fkey FOREIGN KEY (processing_id) REFERENCES vitalia_document_processing (id);
ALTER TABLE vitalia_professional_reviews ADD CONSTRAINT vitalia_professional_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_sessions ADD CONSTRAINT vitalia_sessions_account_id_fkey FOREIGN KEY (account_id) REFERENCES vitalia_accounts (id);
