# Fase 5 — Revisión profesional

El usuario confirmó consulta profesional funcionando con imagen sin texto (sin extracción) y PDF ficticio (datos correspondientes). Se agrega revisión/aprobación humana separada.

Profesional asignado: coteja original, corrige copia, explica cambios/ausencias y confirma antes de aprobar. Registro conserva revisor, fecha, observaciones y snapshots original/revisado. Trigger y unicidad impiden sobrescrituras o eliminación. La IA permanece sin aprobación automática.

Paciente: etiqueta Revisión profesional registrada, sin publicar todavía los datos revisados. El procesamiento original no cambia de estado ni contenido.

Compilación y 268 pruebas backend aprobadas en 32 suites. Pendientes en Windows: migración 009, verificación PostgreSQL con datos sintéticos revertidos, flutter analyze, pruebas Flutter y flujo visual de aprobación. No se aplicó migración a la base del usuario desde aquí.

Siguiente: presentación al paciente de la copia revisada y después explicación simple asistida, con controles de calidad. Versionado/rectificación de revisiones y automatización/recuperación de procesamiento siguen pendientes.
