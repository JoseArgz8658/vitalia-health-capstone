# CAM-034 — Explicación ampliada y chat vinculado a examen

## Autorización
El 06-10-2026 el usuario autorizó ampliar la explicación y crear el chatbot, persistencia, backend, Flutter, pruebas y documentación. Pidió conocimiento general relevante al examen y rechazo de temas externos/otros documentos, sin inventar, diagnosticar, recetar ni recomendar. El rediseño visual queda pendiente.

## Implementación
Migración 011 y nuevo módulo exam-assistant: contrato/política, cliente local, servicio transaccional con memoria e idempotencia, router y evaluación ficticia. app/server conectan el servicio y exigen las tablas. AuthApi añade rutas assistant, espera mayor y mensajes específicos. ExplicacionApi pasa a versión 2; se añade ChatExamenApi/Panel en revisión paciente y sus pruebas. Explicaciones versión 1 y revisiones originales se conservan sin reescritura. Sin dependencias nuevas ni secretos.

## Validación y límites
Pruebas backend: permisos y contexto, límites, mensajes repetidos, concurrencia entre instancias simuladas, recuperación de intento vencido, bloqueo de recomendaciones/diagnóstico, entrada maliciosa, transporte y memoria acotada. Compilación TypeScript y batería completa: 345 pruebas backend en 35 suites aprobadas. Verificador PostgreSQL, pruebas Flutter y evaluación de once casos con modelo real preparados para Windows; no ejecutados aquí.

Filtros y prompts no prueban la verdad médica. Respuestas libres requieren revisión semántica y evaluación ampliada en la siguiente fase. No se certifica que el modelo conozca todos los temas médicos ni que siempre sea coherente. Datos numéricos se conservan desde la revisión, fuera de la prosa del modelo.

## Reversión
Volver a fase-5/explicacion-examen y reiniciar backend/Flutter. Conservar tablas 011 sin uso; no borrar datos ni reescribir historial de migraciones. V1 permanece en tabla 010 y disponible para reversión.
