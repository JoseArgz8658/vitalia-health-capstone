# Diccionario añadido en fase 7.1

Documenté las ocho tablas implementadas en 012_profiles_locations. Este diccionario complementa el esquema anterior; no convierte las demás entidades propuestas en tablas implementadas. Las reglas completas están en el SQL PostgreSQL y la guía del bloque. (José Aránguiz)

Estado: código preparado; aplicación en la base del equipo pendiente.

## vitalia_people

| Atributo | Tipo PostgreSQL | Permite NULL |
|---|---|---|
| id | uuid | No |
| account_id | uuid | No |
| first_name | text | No |
| additional_names | text | Sí |
| first_surname | text | No |
| second_surname | text | Sí |
| birth_date | date | Sí |
| phone | text | Sí |
| preferred_commune_code | text | Sí |
| created_at | timestamptz | No |
| updated_at | timestamptz | No |

PK: id.
UNIQUE: account_id.
FK: account_id → vitalia_accounts(id).
FK: preferred_commune_code → vitalia_communes(code).

## vitalia_person_identifiers

| Atributo | Tipo PostgreSQL | Permite NULL |
|---|---|---|
| id | uuid | No |
| person_id | uuid | No |
| country_code | text | No |
| identifier_type | text | No |
| normalized_value | text | No |
| verification_status | text | No |
| created_at | timestamptz | No |

PK: id.
UNIQUE: country_code, identifier_type, normalized_value.
UNIQUE: person_id, country_code, identifier_type.
FK: person_id → vitalia_people(id).

## vitalia_patient_profiles

| Atributo | Tipo PostgreSQL | Permite NULL |
|---|---|---|
| person_id | uuid | No |
| created_at | timestamptz | No |

PK: person_id.
FK: person_id → vitalia_people(id).

## vitalia_patient_measurements

| Atributo | Tipo PostgreSQL | Permite NULL |
|---|---|---|
| id | uuid | No |
| patient_person_id | uuid | No |
| measured_at | timestamptz | No |
| weight_kg | numeric | Sí |
| height_cm | numeric | Sí |
| source | text | No |
| recorded_by | uuid | No |
| created_at | timestamptz | No |

PK: id.
FK: patient_person_id → vitalia_patient_profiles(person_id).
FK: recorded_by → vitalia_accounts(id).

## vitalia_professional_profiles

| Atributo | Tipo PostgreSQL | Permite NULL |
|---|---|---|
| person_id | uuid | No |
| registration_reference | text | Sí |
| verification_status | text | No |
| created_at | timestamptz | No |
| updated_at | timestamptz | No |

PK: person_id.
FK: person_id → vitalia_people(id).

## vitalia_regions

| Atributo | Tipo PostgreSQL | Permite NULL |
|---|---|---|
| code | text | No |
| name | text | No |

PK: code.

## vitalia_provinces

| Atributo | Tipo PostgreSQL | Permite NULL |
|---|---|---|
| code | text | No |
| region_code | text | No |
| name | text | No |

PK: code.
FK: region_code → vitalia_regions(code).

## vitalia_communes

| Atributo | Tipo PostgreSQL | Permite NULL |
|---|---|---|
| code | text | No |
| province_code | text | No |
| name | text | No |

PK: code.
FK: province_code → vitalia_provinces(code).
