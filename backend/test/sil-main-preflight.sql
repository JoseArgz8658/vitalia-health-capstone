-- Diagnóstico de compatibilidad para integrar el SIL a la aplicación
-- principal Vitalia. SÓLO METADATOS, sin consultar datos de pacientes.
-- Ejecutar exclusivamente contra vitalia-postgres-1, en modo lectura.
BEGIN TRANSACTION READ ONLY;

SELECT current_database() AS base_actual,
       current_user AS usuario_bd,
       current_setting('transaction_read_only') AS solo_lectura;

-- Las migraciones 036 y 037 son EXCLUSIVAS de la demo. Su ausencia
-- en la base principal es correcta: no deben trasladarse directamente.
WITH required(version, scope) AS (
  VALUES
    ('026_sil_orders','sil'),
    ('027_sil_catalog','sil'),
    ('028_sil_order_numbers','sil'),
    ('029_sil_traceability','sil'),
    ('030_sil_review_workflow','sil'),
    ('031_sil_external_reports','sil'),
    ('032_sil_audit_download','sil'),
    ('033_sil_branches_patient_demo','compatibilidad_ficticia'),
    ('034_sil_medical_requests_demo','compatibilidad_ficticia'),
    ('035_sil_retire_validator_role','sil'),
    ('036_sil_portal_invites_demo','solo_demo_no_migrar'),
    ('037_sil_patient_recovery_demo','solo_demo_no_migrar')
)
SELECT r.version AS migracion, r.scope AS alcance,
       CASE WHEN m.version IS NOT NULL THEN 'APLICADA'
            ELSE 'NO_APLICADA' END AS estado
FROM required r
LEFT JOIN public.vitalia_schema_migrations m ON m.version=r.version
ORDER BY r.version;

-- Únicamente existencia de objetos. No lee filas clínicas ni credenciales.
WITH required(tabla, scope) AS (
  VALUES
    ('vitalia_accounts','principal'),
    ('vitalia_account_roles','principal'),
    ('vitalia_sessions','principal'),
    ('vitalia_documents','principal'),
    ('vitalia_document_audit','principal'),
    ('vitalia_sil_orders','sil'),
    ('vitalia_sil_order_exams','sil'),
    ('vitalia_sil_exam_catalog','sil'),
    ('vitalia_sil_samples','sil'),
    ('vitalia_sil_results','sil'),
    ('vitalia_sil_audit','sil'),
    ('vitalia_sil_external_reports','sil'),
    ('vitalia_sil_branches','compatibilidad_ficticia'),
    ('vitalia_sil_patient_profiles_demo','compatibilidad_ficticia'),
    ('vitalia_sil_medical_requests_demo','compatibilidad_ficticia'),
    ('vitalia_sil_portal_access_demo','solo_demo_no_migrar'),
    ('vitalia_sil_patient_recovery_demo','solo_demo_no_migrar')
)
SELECT tabla, scope AS alcance,
       CASE WHEN to_regclass('public.' || tabla) IS NULL
            THEN 'AUSENTE' ELSE 'PRESENTE' END AS estado
FROM required
ORDER BY scope, tabla;

COMMIT;
