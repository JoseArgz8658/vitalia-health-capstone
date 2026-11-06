# Fase 5.18 — Calidad del asistente (en curso)

Se implementan fundamento educativo limitado y control de referencias a filas. Los datos aprobados permanecen separados de las respuestas libres.

## Comprobación local
Desde backend, ejecutar npm test, node dist/exam-assistant/evaluate.js y node dist/exam-assistant/evaluate-quality.js; comprobar LASTEXITCODE después de cada evaluación. No necesita PostgreSQL ni S3. Revisión del prompt 4. Se requiere inspección semántica de respuestas, incluyendo preguntas nuevas; aprobar las baterías no certifica calidad clínica.

## Cierre pendiente
Evaluación real y pruebas Flutter del chat; ampliar cobertura y resolver hallazgos sin ajustar únicamente a ejemplos de prueba.

## Fases siguientes
Procesamiento automático y recuperación; comparación de exámenes compatibles dentro del alcance documentado; diseño y accesibilidad de paciente/profesional/administrador; flujos completos web y Android; despliegue, APK, contratos API y documentación final; limpieza y publicación autorizada. Configuración externa y comandos locales los ejecuta el usuario. No se consideran fases terminadas por preparar código o documentación.
