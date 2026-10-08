# CAM-044 — Valores revisados y errores del asistente

Autorización: continuar las consultas pendientes tras la prueba del usuario (valor de eritrocitos, nombre ausente y explicación fallida).

Consultas factuales de un indicador copian valor/unidad de la revisión, sin Ollama ni modificación del original. Si no hay una fila inequívoca pide el nombre de un indicador. El nombre del paciente no forma parte del contexto: responde esa limitación explícitamente.

La excepción numérica valida respuestas exactas construidas desde la revisión; no admite cifras inventadas, interpretación ni recomendaciones. Los mensajes distinguen solicitud en curso, espera entre intentos, respuesta rechazada y servicio no disponible, con códigos acotados sin contenido interno.

Sin migraciones ni dependencias nuevas. Pruebas del backend y pruebas unitarias Flutter añadidas; Flutter debe verificarse en Windows al no estar instalado en el entorno de desarrollo del agente.

Reversión: revertir este commit.
