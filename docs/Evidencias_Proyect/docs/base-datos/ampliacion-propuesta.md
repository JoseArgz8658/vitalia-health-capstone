# Ampliación propuesta — no implementada

Este documento reúne necesidades expresadas por el usuario. No es una migración aprobada ni una descripción del esquema actual. Antes de implementarlo faltan decisiones de identidad, permisos, aislamiento multiclínica y compatibilidad con cuentas existentes.

| Entidad propuesta | Atributos orientativos | Relaciones y decisiones |
|---|---|---|
| Persona | UUID, RUT normalizado único cuando corresponda, nombres, apellidos, fecha de nacimiento, teléfono | Separar identidad personal de credenciales. Decidir cómo atender personas sin RUT chileno. La validación del dígito no acredita identidad. |
| Perfil paciente | UUID/persona, datos de contacto, ubicación opcional | Fecha de nacimiento permite calcular edad; no mantener edad fija. Peso y altura, si se incorporan, deben tener fecha y unidad. |
| Perfil profesional | UUID/persona, identificación profesional y estado de habilitación | Peso y altura no necesarios para ejercer. Una persona puede ser paciente y profesional: el rol único actual necesitará rediseño. |
| Clínica | UUID, nombre, estado | Definir frontera del tenant: clínica u organización. No basta añadir una columna a la pantalla. |
| Sucursal | UUID, clínica, comuna, calle, número, piso opcional y contacto | Clínica 1:N sucursales. Usar direcciones ficticias en pruebas. |
| Región / provincia / comuna | Código, nombre, referencia territorial padre | Elegir catálogo oficial y verificarlo antes de cargar datos. Ciudad/localidad no debe tratarse automáticamente como sinónimo de comuna. |
| Especialidad | UUID o código, nombre, estado | Catálogo y relación N:M con profesionales. |
| Profesional por clínica/sucursal | Profesional, clínica/sucursal, rol clínico y estado | Jefe clínico crea/gestiona profesionales dentro de su clínica; separar de administrador técnico. |
| Atención o asignación por examen | Documento, paciente, profesional, sucursal, estado, fechas | El paciente elige profesional; opción general y derivación autorizada. Revisar transición desde asignación paciente-profesional actual. |
| Derivación | Examen/atención, origen, destino, motivo, actor, fecha | Registrar trazabilidad y límites de acceso entre profesionales/clínicas. |
| Notificación | Destinatario, evento, documento, fecha, estado de lectura | Separar notificación persistida de entrega push móvil y sus dispositivos. |

## Decisiones pendientes antes del DDL

- Qué datos son obligatorios y qué ocurre con pacientes sin RUT o sin teléfono.
- Identidad global de paciente frente a pertenencia clínica; consentimientos y acceso entre tenants.
- Cuenta con varios roles y cómo conservar sesiones existentes.
- Medidas personales opcionales con unidad, fecha y finalidad; no incorporarlas al chat automáticamente.
- Acceso al chat con datos aún no revisados: solicitud del usuario pendiente, actualmente se exige revisión aprobada. Necesita diseño y validación propios.
- Si mantener resultados como JSONB o añadir tablas normalizadas; conservar original, revisión y trazabilidad durante la transición.
- Migración compatible, datos de prueba y pruebas de aislamiento/permisos.

Primero cerrar el modelo actual como evidencia. Luego acordar el modelo ampliado, implementarlo mediante migraciones y actualizar backend, formularios y pruebas en un bloque independiente. No crear datos de clínicas verdaderas ni datos personales reales para la demo.
