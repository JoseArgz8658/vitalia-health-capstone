# Diseño ampliado, bloque 1 — propuesta para revisión
Estado: NO implementado. Base real: 17 tablas / 123 columnas / 35 FK, según inventario del usuario. No sustituir el modelo actual ni ejecutar migraciones a partir de este documento.

## Criterios de este borrador
- Conservar vitalia_accounts como cuenta de acceso y sus UUID. No duplicar password_hash ni correo de acceso en perfiles.
- Separar persona, perfil paciente y perfil profesional. Una persona puede tener ambos perfiles.
- El RUT no será PK: la identidad interna continúa siendo UUID. Un RUT, cuando se registre, será único normalizado; el cálculo de su dígito no prueba la identidad de quien se registra.
- Clínica será el tenant de este primer diseño; sucursal pertenece a una clínica. El paciente puede mantener exámenes privados sin clínica asignada.
- La pertenencia clínica y la atención autorizan acceso; compartir clínica no permite consultar todos los exámenes.
- No migrar ni reemplazar el role_code actual hasta diseñar la compatibilidad de sesiones/API y permisos con varios perfiles.

Obligatorio aquí significa NOT NULL propuesto al persistir una fila. No implica pedir todos los datos en el primer formulario ni completar cuentas antiguas con información inventada.

## A. Identidad y perfiles

### vitalia_people
| Atributo | Tipo propuesto | Obligatorio | Regla |
|---|---|---|---|
| id | uuid | Sí | PK |
| account_id | uuid | Sí | FK accounts.id; UNIQUE |
| first_name | text | Sí | Texto no vacío |
| additional_names | text | No | No exigir segundo nombre |
| first_surname | text | Sí | Texto no vacío; nombre de campo neutral |
| second_surname | text | No | No exigir dos apellidos |
| birth_date | date | No | No futura; requerido para completar perfil paciente |
| phone | text | No | Formato a definir; sin inventar teléfono para cuentas antiguas |
| preferred_commune_code | text | No | FK communes.code; preferencia, no dirección exacta |
| created_at | timestamptz | Sí | Fecha de creación |
| updated_at | timestamptz | Sí | Fecha de modificación |

Relación accounts 1 : 0..1 people. La ausencia de perfil representa cuenta antigua/incompleta; no elimina la cuenta. No almacenar edad fija.

### vitalia_person_identifiers
| Atributo | Tipo propuesto | Obligatorio | Regla |
|---|---|---|---|
| id | uuid | Sí | PK |
| person_id | uuid | Sí | FK people.id |
| country_code | text | Sí | País del identificador, catálogo por definir |
| identifier_type | text | Sí | RUT u otro tipo admitido por política |
| normalized_value | text | Sí | Valor normalizado; UNIQUE(country_code, identifier_type, normalized_value) |
| verification_status | text | Sí | not_verified / verified, sin aprobación automática por formato |
| created_at | timestamptz | Sí | Registro |

UNIQUE(person_id, country_code, identifier_type) como propuesta de un identificador vigente por tipo/país. El proceso real de verificación queda pendiente; ninguna pantalla debe marcar verificado por calcular módulo 11. RUT obligatorio para nuevos pacientes chilenos es una decisión pendiente, con alternativa para quien no disponga de él.

### vitalia_patient_profiles
| Atributo | Tipo propuesto | Obligatorio | Regla |
|---|---|---|---|
| person_id | uuid | Sí | PK y FK people.id |
| created_at | timestamptz | Sí | Registro |

La información demográfica se comparte desde people; no repetir correo, RUT ni nombres. El perfil completo requerirá fecha de nacimiento. La dirección exacta es opcional y no forma parte de este bloque.

### vitalia_patient_measurements
| Atributo | Tipo propuesto | Obligatorio | Regla |
|---|---|---|---|
| id | uuid | Sí | PK |
| patient_person_id | uuid | Sí | FK patient_profiles.person_id |
| measured_at | timestamptz | Sí | Fecha del dato |
| weight_kg | numeric | No | Mayor que cero |
| height_cm | numeric | No | Mayor que cero |
| source | text | Sí | patient_reported / professional_recorded |
| recorded_by | uuid | Sí | FK accounts.id |
| created_at | timestamptz | Sí | Registro |

CHECK al menos una medida no nula. Unidades fijas en el nombre evitan mezclar centímetros y metros. Fuente declarada no equivale a medición clínica validada. No enviar automáticamente estos datos al chat.

### vitalia_professional_profiles
| Atributo | Tipo propuesto | Obligatorio | Regla |
|---|---|---|---|
| person_id | uuid | Sí | PK y FK people.id |
| registration_reference | text | No | Referencia profesional; formato/procedimiento por definir |
| verification_status | text | Sí | pending / verified / rejected |
| created_at | timestamptz | Sí | Registro |
| updated_at | timestamptz | Sí | Actualización |

No confundir al médico mencionado en un PDF con un profesional que tenga cuenta. Su habilitación no se acredita con una cadena de texto ni con el RUT.

## B. Ubicación y clínicas
No se cargan catálogos territoriales sin revisar una fuente oficial. Ciudad/localidad no se equipara automáticamente a comuna.

| Tabla | Atributos obligatorios | Atributos opcionales | Claves |
|---|---|---|---|
| vitalia_regions | code text, name text | — | PK code |
| vitalia_provinces | code text, region_code text, name text | — | PK code; FK region_code → regions.code |
| vitalia_communes | code text, province_code text, name text | — | PK code; FK province_code → provinces.code |
| vitalia_clinics | id uuid, name text, active boolean, created_at timestamptz | contact_phone text | PK id |
| vitalia_branches | id uuid, clinic_id uuid, commune_code text, name text, street text, address_number text, active boolean, created_at timestamptz | floor text, unit text, contact_phone text | PK id; FK clinic_id → clinics.id; FK commune_code → communes.code; UNIQUE(clinic_id,id) |

Número, piso y unidad como texto permiten s/n u otros formatos sin inventar ceros. Las clínicas y direcciones de demo serán ficticias. El filtro por comuna permite elegir sede sin solicitar dirección exacta del paciente. No implica geolocalización ni cálculo automático de la clínica más cercana.

## C. Profesionales, especialidades y acceso

| Tabla | Atributos | Claves y reglas |
|---|---|---|
| vitalia_specialties | id uuid, name text, active boolean | PK id; UNIQUE name como propuesta de catálogo controlado |
| vitalia_professional_specialties | professional_person_id uuid, specialty_id uuid | PK compuesta; FK a professional_profiles y specialties |
| vitalia_clinic_memberships | id uuid, clinic_id uuid, professional_person_id uuid, clinical_role text, active boolean, created_at timestamptz, updated_at timestamptz | PK id; UNIQUE(clinic_id,professional_person_id); UNIQUE(clinic_id,id); FK a clinics y professional_profiles |
| vitalia_branch_memberships | clinic_id uuid, branch_id uuid, membership_id uuid | PK(branch_id,membership_id); FK compuesta(clinic_id,branch_id) → branches(clinic_id,id); FK compuesta(clinic_id,membership_id) → clinic_memberships(clinic_id,id) |

clinical_role propuesto: clinician / clinical_chief. La medicina general es especialidad, no permiso automático de derivación. El permiso de derivar se define explícitamente en backend. No ampliar el CHECK de vitalia_roles antes de acordar cómo distinguir roles globales de pertenencias clínicas.

Un jefe clínico gestiona profesionales de SU clínica mediante API autorizada; no crea pertenencias en otras clínicas. Administrador técnico no asigna pacientes ni recibe acceso a registros clínicos por su rol. Esto es objetivo futuro: la asignación administrativa provisional del código actual aún existe.

## D. Atención por examen y derivación

### vitalia_exam_care
| Atributo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| id | uuid | Sí | PK |
| document_id | uuid | Sí | FK documents.id |
| clinic_id | uuid | Sí | FK clinics.id |
| branch_id | uuid | Sí | FK(clinic_id,branch_id) → branches(clinic_id,id) |
| membership_id | uuid | Sí | FK(clinic_id,membership_id) → clinic_memberships(clinic_id,id) |
| status | text | Sí | requested / active / closed / cancelled |
| requested_by | uuid | Sí | FK accounts.id |
| requested_at | timestamptz | Sí | Registro de elección |
| closed_at | timestamptz | No | Cierre |

Comprobar que el profesional trabaja en la sucursal mediante branch_memberships. Índice único parcial(document_id) WHERE status IN ('requested','active') propuesto: una atención abierta por examen; historial de atenciones cerradas conservado. Un documento puede no tener atención y permanecer privado.

No repetir patient_id aquí: el propietario está en documents.patient_id. Backend debe verificar que requested_by es el propietario o actor autorizado. La FK a accounts no acredita ese permiso. Si se permite atención simultánea, esta restricción debe revisarse antes de implementar.

### vitalia_exam_referrals
| Atributo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| id | uuid | Sí | PK |
| care_id | uuid | Sí | FK exam_care.id |
| clinic_id | uuid | Sí | Debe coincidir con atención |
| from_membership_id | uuid | Sí | FK(clinic_id,from_membership_id) → clinic_memberships(clinic_id,id) |
| to_membership_id | uuid | Sí | FK(clinic_id,to_membership_id) → clinic_memberships(clinic_id,id) |
| reason | text | Sí | Texto no vacío |
| created_by | uuid | Sí | FK accounts.id |
| created_at | timestamptz | Sí | Registro |

CHECK origen distinto de destino. Añadir UNIQUE(clinic_id,id) a exam_care y FK compuesta(clinic_id,care_id) para coherencia clínica al definir el DDL. No permitir derivación entre clínicas en este primer bloque. No sobrescribir la autoría de revisiones aprobadas al reasignar la atención.

## E. Transición y pruebas requeridas
1. Crear tablas nuevas sin borrar ni renombrar accounts/documents/reviews/chat existentes.
2. No fabricar RUT ni nombres a partir del PDF o correo. Pedir completar perfil a cuentas antiguas.
3. Mantener el inicio de sesión actual durante transición; habilitar nuevos permisos por actor y pertenencia, no por campos enviados por Flutter.
4. Decidir migración de patient_assignments a exam_care. No convertir todas las asignaciones a una clínica supuesta.
5. Mantener revisión original inmutable y snapshots de chat. Las nuevas relaciones no deben cambiar el significado de aprobaciones anteriores.
6. Tests de misma persona paciente/profesional; duplicidad de identificador; perfil incompleto; sede/profesional de distinta clínica; propietario del documento; derivación autorizada/revocada; revisión previa conservada.
7. Verificar API/worker con usuario PostgreSQL limitado antes de despliegue; pendiente de seguridad ya documentado.

Notificaciones/push, direcciones personales y chat con extracción no aprobada quedan en bloques posteriores. No son necesarios para dibujar esta primera ampliación.

## Decisiones para cerrar antes de implementar
- Confirmar clínica como tenant, una atención abierta por examen y derivación inicialmente dentro de clínica.
- Identificación obligatoria y alternativas sin RUT; teléfono obligatorio al completar perfil o solo recomendado.
- Registro global de profesionales por jefe clínico y asignación inicial de jefes sin dar acceso clínico a administrador técnico.
- Política de perfiles dobles y compatibilidad con role_code/sesiones actuales.

Este borrador permite revisar atributos y relaciones; todavía no corresponde a una base desplegada ni a un modelo final aprobado.
