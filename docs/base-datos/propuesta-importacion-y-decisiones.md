# Modelo ampliado: decisiones y uso del DDL visual

Estado: propuesta, no implementada. Decisiones confirmadas por el usuario: un médico responsable a la vez por examen, segunda opinión posterior, derivaciones dentro de la misma clínica y teléfono opcional. No aplicar este DDL a PostgreSQL.

## Importación
1. Guarda y cierra el diseño actual sin cambiarlo.
2. Crea un diseño nuevo y guárdalo como Vitalia_propuesta.
3. Archivo > Importar > Archivo DDL: selecciona vitalia-propuesta-datamodeler.sql.
4. Usa Oracle Database 21c. Importa y fusiona todas las tablas en el diseño nuevo.
5. El archivo contiene 35 tablas: 17 actuales más 18 propuestas. Contiene 228 columnas y 68 FK (123/35 actuales + 105/33 nuevas). Contar FK significa restricciones, no columnas; hay referencias compuestas.
6. Guarda el resultado y revisa avisos del parser. Esta importación aún no se ha ejecutado aquí.

No importar encima de Vitalia_actual: conservarlo como evidencia real. La propuesta incorpora tablas actuales para visualizar las conexiones; eso no convierte a las tablas nuevas en implementadas.

## Nuevas tablas
- vitalia_account_roles: pertenencia a varios roles globales. Propuesta de transición; role_code actual permanece visible en la base de referencia y necesita compatibilidad antes de reemplazarse.
- vitalia_people, vitalia_person_identifiers, vitalia_patient_profiles, vitalia_professional_profiles y vitalia_patient_measurements.
- vitalia_regions, vitalia_provinces y vitalia_communes.
- vitalia_clinics y vitalia_branches.
- vitalia_specialties y vitalia_professional_specialties.
- vitalia_clinic_memberships y vitalia_branch_memberships.
- vitalia_exam_care, vitalia_exam_referrals y vitalia_care_reviews.

Los atributos, tipos PostgreSQL propuestos y nulabilidad están en propuesta-estructura.json. Las equivalencias visuales Oracle son las de importar-ddl.md; numeric se representa con NUMBER sin fijar todavía precisión clínica. No usar VARCHAR2(4000) como requisito real de longitud.

## Responsabilidad y segunda opinión
exam_care conserva la atención por documento/sede/profesional. purpose propuesto: initial_review o second_opinion. prior_review_id enlaza la revisión previa de la nueva estructura cuando exista; no debe apuntar a otro documento. No insertar un UUID de professional_reviews en esa FK: la transición de revisiones antiguas requiere un procedimiento explícito.

care_reviews permite una revisión por atención (UNIQUE care_id), pero varias atenciones pueden referenciar el mismo procesamiento. Se preserva la extracción IA y cada copia profesional. Las filas profesionales antiguas siguen en professional_reviews, cuya restricción actual no se cambia en este DDL. Debe diseñarse cómo API/chat leen revisiones antiguas y nuevas antes de migrar; no duplicar aprobaciones sin documentar su origen.

Para garantizar un responsable por examen se necesita en PostgreSQL un índice único parcial sobre exam_care(document_id) WHERE status IN ('requested','active'). No se incluye en el DDL Oracle de importación. Este diagrama por sí solo no demuestra ese límite.

Una atención cerrada no se vuelve a abrir automáticamente para pedir otra opinión. La nueva atención conserva referencia a la revisión anterior; el historial no se sobrescribe. Cambiar de clínica para una segunda opinión necesita consentimiento y diseño de acceso adicionales; no se habilita en este bloque.

## Derivación
Las FK compuestas clinic_id/membership y clinic_id/care obligan a referenciar la misma clínica en el diseño. Cada nuevo responsable debe tener pertenencia vigente a la sucursal. La transferencia debe ser transaccional, autorizada y auditada, sin crear dos responsables activos. No editar al autor de una revisión ya guardada.

La derivación a otro profesional queda en exam_referrals. CHECK origen distinto de destino, autorización del actor, estados de pertenencia y motivo no vacío son reglas pendientes del DDL PostgreSQL/backend, no garantías del archivo visual.

## Pendientes que el dibujo no implementa
- CHECK/estados, índices parciales, predeterminados, unidades positivas, obligatoriedad contextual de fecha de nacimiento, RUT y su verificación.
- Propietario real del documento, profesional habilitado, jefe clínico dentro de su tenant, revisión previa del mismo examen y permisos de transferencia.
- Compatibilidad de roles/sesiones y revisiones antiguas; consentimiento y segunda opinión entre clínicas.
- Verificación de catálogos oficiales y notificaciones.

Se conservan las PK, UNIQUE completas, FK y nulabilidad de la propuesta; no se afirman permisos, inmutabilidad o aislamiento implementados por dibujar relaciones. Antes de migraciones: revisar estructura y probar integridad, acceso e historia con datos ficticios.
