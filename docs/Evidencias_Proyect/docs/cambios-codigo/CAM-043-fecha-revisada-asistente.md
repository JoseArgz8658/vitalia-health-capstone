# CAM-043 — Consulta de fecha revisada

Autorización: continuar fases pendientes, incluida la consulta de fecha reportada por el usuario.

Respuesta directa desde la fecha de la revisión profesional, sin Ollama. La excepción numérica solo admite el texto exacto generado por el backend. Sin cambios de contrato ni migraciones.

No distingue fecha de muestra y emisión: el esquema guarda una sola fecha. No inventa fecha ausente o imposible, ni atribuye un evento específico.

Pruebas: fecha directa, calendario, ausencia, evento ambiguo, inyección, otro examen y rechazo de texto/cifras modificadas; suite completa backend.

Reversión: revertir commit; sin cambios PostgreSQL.
