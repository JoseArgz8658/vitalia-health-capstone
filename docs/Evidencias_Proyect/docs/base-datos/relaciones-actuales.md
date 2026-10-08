# Relaciones del esquema implementado

Se derivan de FK, nulabilidad y restricciones PK/UNIQUE del inventario. La cardinalidad inversa permite cero filas hijas: la FK no obliga a un padre a tener hijos. Los índices únicos parciales no se interpretan como unicidad general.

| Tabla hija / FK | Tabla referenciada | Padre por fila hija | Hijas por padre |
|---|---|---|---|
| vitalia_accounts (role_code) | vitalia_roles (code) | 1 | 0..N |
| vitalia_assignment_audit (actor_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_assignment_audit (assignment_id) | vitalia_patient_assignments (id) | 1 | 0..N |
| vitalia_document_audit (account_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_document_audit (document_id) | vitalia_documents (id) | 0..1 | 0..N |
| vitalia_document_cleanup (document_id) | vitalia_documents (id) | 1 | 0..1 |
| vitalia_document_processing (document_id) | vitalia_documents (id) | 1 | 0..1 |
| vitalia_documents (patient_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_exam_assistant_audit (document_id) | vitalia_documents (id) | 1 | 0..N |
| vitalia_exam_assistant_audit (patient_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_exam_assistant_threads (document_id) | vitalia_documents (id) | 1 | 0..N |
| vitalia_exam_assistant_threads (patient_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_exam_assistant_threads (review_id) | vitalia_professional_reviews (id) | 1 | 0..1 |
| vitalia_exam_assistant_turns (thread_id) | vitalia_exam_assistant_threads (id) | 1 | 0..N |
| vitalia_exam_explanations (document_id) | vitalia_documents (id) | 1 | 0..N |
| vitalia_exam_explanations (patient_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_exam_explanations (review_id) | vitalia_professional_reviews (id) | 1 | 0..1 |
| vitalia_explanation_audit (document_id) | vitalia_documents (id) | 1 | 0..N |
| vitalia_explanation_audit (patient_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_explanation_audit (review_id) | vitalia_professional_reviews (id) | 0..1 | 0..N |
| vitalia_patient_assignments (created_by) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_patient_assignments (patient_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_patient_assignments (professional_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_patient_assignments (updated_by) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_professional_access_audit (assignment_id) | vitalia_patient_assignments (id) | 1 | 0..N |
| vitalia_professional_access_audit (document_id) | vitalia_documents (id) | 0..1 | 0..N |
| vitalia_professional_access_audit (patient_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_professional_access_audit (processing_id) | vitalia_document_processing (id) | 0..1 | 0..N |
| vitalia_professional_access_audit (professional_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_professional_reviews (assignment_id) | vitalia_patient_assignments (id) | 1 | 0..N |
| vitalia_professional_reviews (document_id) | vitalia_documents (id) | 1 | 0..N |
| vitalia_professional_reviews (patient_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_professional_reviews (processing_id) | vitalia_document_processing (id) | 1 | 0..1 |
| vitalia_professional_reviews (reviewer_id) | vitalia_accounts (id) | 1 | 0..N |
| vitalia_sessions (account_id) | vitalia_accounts (id) | 1 | 0..N |

## Lectura del modelo

- Paciente, profesional y actores de auditoría apuntan a vitalia_accounts. La FK no verifica por sí sola el rol del titular.
- vitalia_document_processing.document_id es UNIQUE: cada documento admite como máximo un registro de procesamiento en este esquema.
- vitalia_professional_reviews.processing_id es UNIQUE: un procesamiento admite como máximo una revisión guardada.
- Las explicaciones y conversaciones tienen review_id UNIQUE: como máximo una de cada una por revisión.
- Los valores clínicos se conservan dentro de JSONB; no hay FK hacia una tabla independiente de resultados.
- vitalia_schema_migrations no tiene FK. Documentar como tabla técnica, no como entidad clínica.
- No concluir que una tabla está sin uso porque no tenga relaciones, esté vacía o tenga un nombre técnico. La comprobación de uso necesita el código.
