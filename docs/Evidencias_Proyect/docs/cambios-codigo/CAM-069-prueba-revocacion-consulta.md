# CAM-069 — Prueba de revocación en consulta dedicada

El usuario ejecutó flutter analyze sin incidencias y flutter test: 75 aprobadas y una fallida. La prueba de revocación buscaba Actualizar historial dentro de la nueva consulta dedicada. Se actualizó a Actualizar extracción, incluyendo ensureVisible y respuesta de revisión válida en el mock.

Se comprueba que la extracción está visible antes de revocar y que el 404 oculta cifras, texto original, controles de aprobación, consulta y documentos. Se conservan las verificaciones de error y no se cambia código de permisos ni se debilita la protección.

Flutter no disponible en este entorno. Repetir flutter test test/profesional_test.dart y después flutter test. No se declara aún resultado de la corrección.
