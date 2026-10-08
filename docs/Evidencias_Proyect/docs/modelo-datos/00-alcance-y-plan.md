# Base de datos: estado actual y fase de modelado

Fecha: 7 de octubre de 2026. Estado: planificación, no esquema final ni migración nueva.

## Cuándo se hará

Cerrar los ajustes actuales del asistente; a continuación realizar una fase dedicada al modelado de datos, antes de implementar clínicas, jefatura clínica, selección de médico y derivaciones. El diseño se revisa primero y solo después se escriben migraciones. No se reconstruye ni borra la base de datos actual.

Entregables: modelo lógico, modelo relacional para Oracle SQL Developer Data Modeler, diccionario de atributos, PK/FK, nulabilidad, restricciones, cardinalidades, reglas de acceso entre clínicas, DDL para PostgreSQL, capturas/exportación PDF del diagrama y evidencia de migración y verificación. El archivo nativo de Data Modeler y sus capturas deben corresponder a la misma versión del modelo y al SQL documentado. No se afirma que un modelo futuro ya esté implementado.

## Lo que ya está implementado

Fuente verificable: backend/database/migrations/001_accounts.sql a 011_exam_assistant.sql.

| Tabla física actual | Función |
|---|---|
| vitalia_roles | Roles actuales: paciente, profesional y administrador |
| vitalia_accounts | Cuenta, correo, hash de contraseña y rol |
| vitalia_sessions | Sesiones de autenticación |
| vitalia_documents | Paciente propietario, datos de carga y clave del objeto S3 |
| vitalia_document_audit | Auditoría de operaciones de documentos |
| vitalia_document_cleanup | Recuperación y limpieza de cargas |
| vitalia_document_processing | Trabajo, estado, versión y resultado de extracción |
| vitalia_patient_assignments | Asignación actual paciente-profesional |
| vitalia_assignment_audit | Auditoría de asignaciones |
| vitalia_professional_access_audit | Auditoría de consultas profesionales |
| vitalia_professional_reviews | Copia revisada, profesional y observaciones |
| vitalia_exam_explanations | Explicación educativa persistida |
| vitalia_explanation_audit | Auditoría de explicaciones |
| vitalia_exam_assistant_threads | Conversación ligada al documento y revisión |
| vitalia_exam_assistant_turns | Preguntas, respuestas y estado de cada solicitud |
| vitalia_exam_assistant_audit | Auditoría del asistente |

Paciente y profesional son actualmente cuentas con roles, no tablas de perfil independientes. Los resultados e informe extraídos y revisados están contenidos en JSONB: no existe todavía una fila relacional por indicador. Historial clínico es actualmente una consulta de documentos, no una tabla independiente. El archivo PDF/PNG/JPEG está en S3; PostgreSQL conserva sus metadatos y referencia. No hay aislamiento por clínica implementado aún.

## Propuesta para estudiar en el modelo futuro

Los nombres siguientes son entidades candidatas, no nombres físicos definitivos.

| Entidad candidata | Atributos candidatos | Relaciones y decisiones |
|---|---|---|
| Región | id, código oficial, nombre | Catálogo territorial; no datos inventados |
| Provincia | id, región_id, código oficial, nombre | Evaluar incluir la jerarquía territorial completa |
| Comuna | id, provincia_id, código oficial, nombre | Región derivada por provincia; evitar duplicar relaciones contradictorias |
| Clínica | id, nombre, estado | Definir frontera tenant y si agrupa varias sedes |
| Sede clínica | id, clínica_id, comuna_id, nombre, calle, número, complemento, piso, localidad | Una clínica puede tener varias ubicaciones |
| Cuenta | id, correo, hash, estado, fechas | Identidad de acceso; no duplicar contraseñas por clínica |
| Paciente | id, cuenta_id, datos de perfil acordados | Perfil distinto del texto transcrito de un informe |
| Profesional | id, cuenta_id, nombre y credenciales acordadas | Separado de pertenencia a clínica |
| Especialidad | id, código, nombre | Evitar especialidad libre como único criterio de selección |
| Profesional-especialidad | profesional_id, especialidad_id | Permitir varias especialidades |
| Membresía clínica | id, clínica_id, profesional_id, estado | Participación del profesional dentro de una clínica |
| Rol y permiso clínico | rol_id, permiso_id, membresía_id | Jefatura y derivación limitadas a su ámbito |
| Examen | id, paciente_id, nombre, tipo, fechas con origen definido | Distinguir carga, toma de muestra y emisión |
| Documento | id, examen_id, tipo MIME, tamaño, nombre, clave S3, fecha de carga, estado | Decidir si un examen admite varios archivos |
| Procesamiento IA | id, documento_id, modelo, versión, estado, fechas, resultado original | Un trabajo compartido; controlar duplicación y versiones |
| Resultado del examen | id, versión_id, orden, nombre, valor textual, unidad, referencia, estado transcrito | Estudiar normalización sin perder literalidad ni unidades |
| Informe transcrito | versión_id, nombres originales, fechas, solicitante, validante, observaciones | Datos del archivo no sustituyen datos de la cuenta |
| Revisión profesional | id, procesamiento_id, profesional_id, copia revisada, observaciones, fecha | Preservar original e inmutabilidad |
| Asignación de examen | id, examen_id, clínica_id, profesional_id, estado, fechas | Elegir y derivar un examen no concede todo el historial |
| Derivación | id, asignación_origen_id, destino, actor, motivo, fecha | Registrar quién derivó y verificar pertenencia a clínica |
| Conversación y turno | id, documento_id, versión de contexto, pregunta, respuesta, estado | Distinguir contexto aprobado y contexto sin revisar |
| Notificación | id, destinatario_id, examen_id, tipo, estado, fechas | Separar registro del evento de entrega push |
| Auditoría | actor, ámbito clínico, operación, recurso, fecha, resultado | Evaluar mantener tablas específicas; no registrar secretos |

## Obligatorios, opcionales y reglas

La fase de diseño fijará la nulabilidad atributo por atributo; esta propuesta no la decide completamente. Toda tabla necesita una clave definida. Las relaciones obligatorias tendrán FK NOT NULL y las opcionales permitirán NULL según el caso. Cuenta requerirá correo válido y hash, nunca contraseña en claro. Documento requerirá propietario/recurso, tipo admitido, tamaño y referencia de almacenamiento.

Para una sede usada en búsqueda territorial: comuna, calle y número o una representación explícita de dirección sin número. Número no debe limitarse a entero: puede incluir letra o S/N. Piso y complemento son opcionales. Ciudad/localidad no se debe tratar como sinónimo de comuna ni crear un catálogo duplicado sin definir su fuente. Catálogos territoriales se cargarán desde una fuente oficial identificada y versionada en la fase correspondiente.

El nombre del paciente o médico dentro del informe puede no coincidir con una cuenta. Se conserva como dato transcrito y revisado, no se vincula automáticamente por coincidencia de nombre. Observación profesional puede ser opcional cuando no hay correcciones ni incidencias; reglas actuales más estrictas no se relajan sin diseño y pruebas.

Antes de modelar se debe resolver: clínica como tenant o una organización con varias clínicas; pertenencia de pacientes a varias clínicas; quién recibe un examen cuando el paciente no elige especialidad; varios documentos por examen; catálogo de especialidades; diferencias entre historial documental e historial clínico completo. Cualquier decisión de acceso se implementa en backend y SQL, no solo ocultando botones.

## Evidencia para Data Modeler

1. Guardar una versión del esquema actual a partir de las migraciones existentes, sin datos médicos ni credenciales.
2. Crear el modelo lógico futuro separado; marcar claramente entidades pendientes.
3. Revisar relaciones, PK/FK, nulabilidad, unicidad, índices, reglas tenant y conservación de versiones.
4. Obtener el modelo relacional y verificar tipos compatibles con PostgreSQL. No ejecutar DDL Oracle sobre PostgreSQL.
5. Generar diccionario y exportación del diagrama con fecha/versión; incluir capturas legibles del modelo completo y grupos de tablas.
6. Crear migraciones incrementales y pruebas de aislamiento, integridad e inmutabilidad; confrontar la base resultante con el modelo documentado.

Esta fase tendrá su propia rama de trabajo y documentación. La distribución limpia conservará la guía de instalación; el material académico de evidencia puede entregarse por separado.
