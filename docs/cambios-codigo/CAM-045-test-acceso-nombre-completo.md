# CAM-045 — Acceso vigente y consulta de nombre completo

Corrección autorizada en continuidad: el usuario reportó el test obsoleto y la variante de pregunta sobre nombre completo.

El test de acceso deja de buscar el botón de validación demo eliminado. Usa el login vigente y un servidor simulado que rechaza credenciales; comprueba que no crea sesión, no consulta identidad ni navega y limpia la contraseña.

El asistente reconoce nombre completo y explica que no está disponible en su contexto revisado, sin enviar la pregunta al modelo. No incorpora datos personales al contexto.

Comprobación del PDF ficticio adjunto, sin versionarlo: el lector PDF conserva los superíndices de las unidades. El chat copia la revisión existente. No modifica revisiones aprobadas ni supone cuál etapa cambió la unidad.

Validación: suite backend y prueba Flutter actualizada (ejecución Flutter pendiente en Windows). Sin migraciones. Reversión: revertir commit.
