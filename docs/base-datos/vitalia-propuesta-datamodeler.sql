-- PROPUESTA NO IMPLEMENTADA. SOLO PARA IMPORTACION VISUAL ORACLE 21c.
-- No ejecutar sobre PostgreSQL. Restricciones de proceso/indices parciales en la guia.
-- BASE ACTUAL (17 tablas) + PROPUESTA (18 tablas): total 35.

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

CREATE TABLE vitalia_account_roles (
    account_id VARCHAR2(36) NOT NULL,
    role_code VARCHAR2(4000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_people (
    id VARCHAR2(36) NOT NULL,
    account_id VARCHAR2(36) NOT NULL,
    first_name VARCHAR2(4000) NOT NULL,
    additional_names VARCHAR2(4000),
    first_surname VARCHAR2(4000) NOT NULL,
    second_surname VARCHAR2(4000),
    birth_date DATE,
    phone VARCHAR2(4000),
    preferred_commune_code VARCHAR2(4000),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_person_identifiers (
    id VARCHAR2(36) NOT NULL,
    person_id VARCHAR2(36) NOT NULL,
    country_code VARCHAR2(4000) NOT NULL,
    identifier_type VARCHAR2(4000) NOT NULL,
    normalized_value VARCHAR2(4000) NOT NULL,
    verification_status VARCHAR2(4000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_patient_profiles (
    person_id VARCHAR2(36) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_patient_measurements (
    id VARCHAR2(36) NOT NULL,
    patient_person_id VARCHAR2(36) NOT NULL,
    measured_at TIMESTAMP WITH TIME ZONE NOT NULL,
    weight_kg NUMBER,
    height_cm NUMBER,
    source VARCHAR2(4000) NOT NULL,
    recorded_by VARCHAR2(36) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_professional_profiles (
    person_id VARCHAR2(36) NOT NULL,
    registration_reference VARCHAR2(4000),
    verification_status VARCHAR2(4000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_regions (
    code VARCHAR2(4000) NOT NULL,
    name VARCHAR2(4000) NOT NULL
);

CREATE TABLE vitalia_provinces (
    code VARCHAR2(4000) NOT NULL,
    region_code VARCHAR2(4000) NOT NULL,
    name VARCHAR2(4000) NOT NULL
);

CREATE TABLE vitalia_communes (
    code VARCHAR2(4000) NOT NULL,
    province_code VARCHAR2(4000) NOT NULL,
    name VARCHAR2(4000) NOT NULL
);

CREATE TABLE vitalia_clinics (
    id VARCHAR2(36) NOT NULL,
    name VARCHAR2(4000) NOT NULL,
    active NUMBER(1) NOT NULL,
    contact_phone VARCHAR2(4000),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_branches (
    id VARCHAR2(36) NOT NULL,
    clinic_id VARCHAR2(36) NOT NULL,
    commune_code VARCHAR2(4000) NOT NULL,
    name VARCHAR2(4000) NOT NULL,
    street VARCHAR2(4000) NOT NULL,
    address_number VARCHAR2(4000) NOT NULL,
    floor VARCHAR2(4000),
    unit VARCHAR2(4000),
    contact_phone VARCHAR2(4000),
    active NUMBER(1) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_specialties (
    id VARCHAR2(36) NOT NULL,
    name VARCHAR2(4000) NOT NULL,
    active NUMBER(1) NOT NULL
);

CREATE TABLE vitalia_professional_specialties (
    professional_person_id VARCHAR2(36) NOT NULL,
    specialty_id VARCHAR2(36) NOT NULL
);

CREATE TABLE vitalia_clinic_memberships (
    id VARCHAR2(36) NOT NULL,
    clinic_id VARCHAR2(36) NOT NULL,
    professional_person_id VARCHAR2(36) NOT NULL,
    clinical_role VARCHAR2(4000) NOT NULL,
    active NUMBER(1) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_branch_memberships (
    clinic_id VARCHAR2(36) NOT NULL,
    branch_id VARCHAR2(36) NOT NULL,
    membership_id VARCHAR2(36) NOT NULL
);

CREATE TABLE vitalia_exam_care (
    id VARCHAR2(36) NOT NULL,
    document_id VARCHAR2(36) NOT NULL,
    clinic_id VARCHAR2(36) NOT NULL,
    branch_id VARCHAR2(36) NOT NULL,
    membership_id VARCHAR2(36) NOT NULL,
    status VARCHAR2(4000) NOT NULL,
    purpose VARCHAR2(4000) NOT NULL,
    prior_review_id VARCHAR2(36),
    requested_by VARCHAR2(36) NOT NULL,
    requested_at TIMESTAMP WITH TIME ZONE NOT NULL,
    closed_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE vitalia_exam_referrals (
    id VARCHAR2(36) NOT NULL,
    care_id VARCHAR2(36) NOT NULL,
    clinic_id VARCHAR2(36) NOT NULL,
    from_membership_id VARCHAR2(36) NOT NULL,
    to_membership_id VARCHAR2(36) NOT NULL,
    reason VARCHAR2(4000) NOT NULL,
    created_by VARCHAR2(36) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE vitalia_care_reviews (
    id VARCHAR2(36) NOT NULL,
    clinic_id VARCHAR2(36) NOT NULL,
    care_id VARCHAR2(36) NOT NULL,
    processing_id VARCHAR2(36) NOT NULL,
    reviewer_membership_id VARCHAR2(36) NOT NULL,
    original_extraction CLOB NOT NULL,
    reviewed_extraction CLOB NOT NULL,
    observations VARCHAR2(4000) NOT NULL,
    confirmed_original NUMBER(1) NOT NULL,
    approved NUMBER(1) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE vitalia_account_roles ADD CONSTRAINT vitalia_account_roles_pk PRIMARY KEY (account_id, role_code);
ALTER TABLE vitalia_people ADD CONSTRAINT vitalia_people_pk PRIMARY KEY (id);
ALTER TABLE vitalia_people ADD CONSTRAINT vitalia_people_uk1 UNIQUE (account_id);
ALTER TABLE vitalia_person_identifiers ADD CONSTRAINT vitalia_person_identifiers_pk PRIMARY KEY (id);
ALTER TABLE vitalia_person_identifiers ADD CONSTRAINT vitalia_person_identifiers_uk1 UNIQUE (country_code, identifier_type, normalized_value);
ALTER TABLE vitalia_person_identifiers ADD CONSTRAINT vitalia_person_identifiers_uk2 UNIQUE (person_id, country_code, identifier_type);
ALTER TABLE vitalia_patient_profiles ADD CONSTRAINT vitalia_patient_profiles_pk PRIMARY KEY (person_id);
ALTER TABLE vitalia_patient_measurements ADD CONSTRAINT vitalia_patient_measurements_pk PRIMARY KEY (id);
ALTER TABLE vitalia_professional_profiles ADD CONSTRAINT vitalia_professional_profiles_pk PRIMARY KEY (person_id);
ALTER TABLE vitalia_regions ADD CONSTRAINT vitalia_regions_pk PRIMARY KEY (code);
ALTER TABLE vitalia_provinces ADD CONSTRAINT vitalia_provinces_pk PRIMARY KEY (code);
ALTER TABLE vitalia_communes ADD CONSTRAINT vitalia_communes_pk PRIMARY KEY (code);
ALTER TABLE vitalia_clinics ADD CONSTRAINT vitalia_clinics_pk PRIMARY KEY (id);
ALTER TABLE vitalia_branches ADD CONSTRAINT vitalia_branches_pk PRIMARY KEY (id);
ALTER TABLE vitalia_branches ADD CONSTRAINT vitalia_branches_uk1 UNIQUE (clinic_id, id);
ALTER TABLE vitalia_specialties ADD CONSTRAINT vitalia_specialties_pk PRIMARY KEY (id);
ALTER TABLE vitalia_specialties ADD CONSTRAINT vitalia_specialties_uk1 UNIQUE (name);
ALTER TABLE vitalia_professional_specialties ADD CONSTRAINT vitalia_professional_specialties_pk PRIMARY KEY (professional_person_id, specialty_id);
ALTER TABLE vitalia_clinic_memberships ADD CONSTRAINT vitalia_clinic_memberships_pk PRIMARY KEY (id);
ALTER TABLE vitalia_clinic_memberships ADD CONSTRAINT vitalia_clinic_memberships_uk1 UNIQUE (clinic_id, professional_person_id);
ALTER TABLE vitalia_clinic_memberships ADD CONSTRAINT vitalia_clinic_memberships_uk2 UNIQUE (clinic_id, id);
ALTER TABLE vitalia_branch_memberships ADD CONSTRAINT vitalia_branch_memberships_pk PRIMARY KEY (branch_id, membership_id);
ALTER TABLE vitalia_exam_care ADD CONSTRAINT vitalia_exam_care_pk PRIMARY KEY (id);
ALTER TABLE vitalia_exam_care ADD CONSTRAINT vitalia_exam_care_uk1 UNIQUE (clinic_id, id);
ALTER TABLE vitalia_exam_referrals ADD CONSTRAINT vitalia_exam_referrals_pk PRIMARY KEY (id);
ALTER TABLE vitalia_care_reviews ADD CONSTRAINT vitalia_care_reviews_pk PRIMARY KEY (id);
ALTER TABLE vitalia_care_reviews ADD CONSTRAINT vitalia_care_reviews_uk1 UNIQUE (care_id);
ALTER TABLE vitalia_account_roles ADD CONSTRAINT vitalia_account_roles_fk1 FOREIGN KEY (account_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_account_roles ADD CONSTRAINT vitalia_account_roles_fk2 FOREIGN KEY (role_code) REFERENCES vitalia_roles (code);
ALTER TABLE vitalia_people ADD CONSTRAINT vitalia_people_fk1 FOREIGN KEY (account_id) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_people ADD CONSTRAINT vitalia_people_fk2 FOREIGN KEY (preferred_commune_code) REFERENCES vitalia_communes (code);
ALTER TABLE vitalia_person_identifiers ADD CONSTRAINT vitalia_person_identifiers_fk1 FOREIGN KEY (person_id) REFERENCES vitalia_people (id);
ALTER TABLE vitalia_patient_profiles ADD CONSTRAINT vitalia_patient_profiles_fk1 FOREIGN KEY (person_id) REFERENCES vitalia_people (id);
ALTER TABLE vitalia_patient_measurements ADD CONSTRAINT vitalia_patient_measurements_fk1 FOREIGN KEY (patient_person_id) REFERENCES vitalia_patient_profiles (person_id);
ALTER TABLE vitalia_patient_measurements ADD CONSTRAINT vitalia_patient_measurements_fk2 FOREIGN KEY (recorded_by) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_professional_profiles ADD CONSTRAINT vitalia_professional_profiles_fk1 FOREIGN KEY (person_id) REFERENCES vitalia_people (id);
ALTER TABLE vitalia_provinces ADD CONSTRAINT vitalia_provinces_fk1 FOREIGN KEY (region_code) REFERENCES vitalia_regions (code);
ALTER TABLE vitalia_communes ADD CONSTRAINT vitalia_communes_fk1 FOREIGN KEY (province_code) REFERENCES vitalia_provinces (code);
ALTER TABLE vitalia_branches ADD CONSTRAINT vitalia_branches_fk1 FOREIGN KEY (clinic_id) REFERENCES vitalia_clinics (id);
ALTER TABLE vitalia_branches ADD CONSTRAINT vitalia_branches_fk2 FOREIGN KEY (commune_code) REFERENCES vitalia_communes (code);
ALTER TABLE vitalia_professional_specialties ADD CONSTRAINT vitalia_professional_specialties_fk1 FOREIGN KEY (professional_person_id) REFERENCES vitalia_professional_profiles (person_id);
ALTER TABLE vitalia_professional_specialties ADD CONSTRAINT vitalia_professional_specialties_fk2 FOREIGN KEY (specialty_id) REFERENCES vitalia_specialties (id);
ALTER TABLE vitalia_clinic_memberships ADD CONSTRAINT vitalia_clinic_memberships_fk1 FOREIGN KEY (clinic_id) REFERENCES vitalia_clinics (id);
ALTER TABLE vitalia_clinic_memberships ADD CONSTRAINT vitalia_clinic_memberships_fk2 FOREIGN KEY (professional_person_id) REFERENCES vitalia_professional_profiles (person_id);
ALTER TABLE vitalia_branch_memberships ADD CONSTRAINT vitalia_branch_memberships_fk1 FOREIGN KEY (clinic_id, branch_id) REFERENCES vitalia_branches (clinic_id, id);
ALTER TABLE vitalia_branch_memberships ADD CONSTRAINT vitalia_branch_memberships_fk2 FOREIGN KEY (clinic_id, membership_id) REFERENCES vitalia_clinic_memberships (clinic_id, id);
ALTER TABLE vitalia_exam_care ADD CONSTRAINT vitalia_exam_care_fk1 FOREIGN KEY (document_id) REFERENCES vitalia_documents (id);
ALTER TABLE vitalia_exam_care ADD CONSTRAINT vitalia_exam_care_fk2 FOREIGN KEY (clinic_id) REFERENCES vitalia_clinics (id);
ALTER TABLE vitalia_exam_care ADD CONSTRAINT vitalia_exam_care_fk3 FOREIGN KEY (branch_id, membership_id) REFERENCES vitalia_branch_memberships (branch_id, membership_id);
ALTER TABLE vitalia_exam_care ADD CONSTRAINT vitalia_exam_care_fk4 FOREIGN KEY (clinic_id, branch_id) REFERENCES vitalia_branches (clinic_id, id);
ALTER TABLE vitalia_exam_care ADD CONSTRAINT vitalia_exam_care_fk5 FOREIGN KEY (clinic_id, membership_id) REFERENCES vitalia_clinic_memberships (clinic_id, id);
ALTER TABLE vitalia_exam_care ADD CONSTRAINT vitalia_exam_care_fk6 FOREIGN KEY (prior_review_id) REFERENCES vitalia_care_reviews (id);
ALTER TABLE vitalia_exam_care ADD CONSTRAINT vitalia_exam_care_fk7 FOREIGN KEY (requested_by) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_exam_referrals ADD CONSTRAINT vitalia_exam_referrals_fk1 FOREIGN KEY (clinic_id, care_id) REFERENCES vitalia_exam_care (clinic_id, id);
ALTER TABLE vitalia_exam_referrals ADD CONSTRAINT vitalia_exam_referrals_fk2 FOREIGN KEY (clinic_id, from_membership_id) REFERENCES vitalia_clinic_memberships (clinic_id, id);
ALTER TABLE vitalia_exam_referrals ADD CONSTRAINT vitalia_exam_referrals_fk3 FOREIGN KEY (clinic_id, to_membership_id) REFERENCES vitalia_clinic_memberships (clinic_id, id);
ALTER TABLE vitalia_exam_referrals ADD CONSTRAINT vitalia_exam_referrals_fk4 FOREIGN KEY (created_by) REFERENCES vitalia_accounts (id);
ALTER TABLE vitalia_care_reviews ADD CONSTRAINT vitalia_care_reviews_fk1 FOREIGN KEY (clinic_id, care_id) REFERENCES vitalia_exam_care (clinic_id, id);
ALTER TABLE vitalia_care_reviews ADD CONSTRAINT vitalia_care_reviews_fk2 FOREIGN KEY (processing_id) REFERENCES vitalia_document_processing (id);
ALTER TABLE vitalia_care_reviews ADD CONSTRAINT vitalia_care_reviews_fk3 FOREIGN KEY (clinic_id, reviewer_membership_id) REFERENCES vitalia_clinic_memberships (clinic_id, id);