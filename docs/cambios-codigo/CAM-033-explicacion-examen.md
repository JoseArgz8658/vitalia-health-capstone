# CAM-033 — Explicación educativa por revisión aprobada

## Autorización
Usuario autorizó el 06-10-2026 el módulo, migración, conexiones backend y Flutter, controles y pruebas. Aclaró que el chatbot forma parte de la propuesta; se acordó implementarlo después de la explicación. No rediseñar visualmente todavía.

## Cambios
Nueva migración 010, servicio/routers/catálogo/generador local, check ficticio y verificador PostgreSQL. app.ts y server.ts conectan el servicio y exigen el esquema. AuthApi permite GET/POST explanation con espera de hasta 150 segundos. Nuevo API/panel Flutter dentro de la copia revisada del paciente. Datos originales y revisiones no se modifican. Sin dependencias nuevas ni .env versionado.

Modelo propone códigos de un catálogo; el backend produce solo textos documentados y conserva las cifras de la revisión. Se rechaza texto libre y conceptos incompatibles. Esto reduce el alcance a definiciones educativas generales; no es interpretación clínica ni chatbot. Catálogo inicial limitado y explícito, véase docs/explicacion-examen.md.

## Validación
Pruebas backend incluyen privacidad del prompt, esquema, catálogo, inyección en nombre, timeout, ausencia de revisión, aislamiento de cuentas, concurrencia, reserva, reutilización, fallo y datos adulterados. Compilación TypeScript y batería completa: 304 pruebas backend en 34 suites aprobadas. Flutter y DB reales no disponibles aquí; pruebas y verificador preparados para Windows. Ollama real también requiere ejecución local.

## Reversión
Volver a la rama fase-5/consulta-revision-paciente y reiniciar backend/Flutter. Tablas 010 pueden conservarse sin uso; no eliminar datos ni reescribir historial de migraciones. No se altera la migración 009.
