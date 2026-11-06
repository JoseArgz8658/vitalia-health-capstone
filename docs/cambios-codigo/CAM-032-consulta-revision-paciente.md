# CAM-032 — Consulta de revisión aprobada por el paciente

## Autorización
El usuario autorizó el módulo, sus conexiones backend/Flutter, pruebas y documentación el 06-10-2026. Mejora visual general aplazada expresamente.

## Implementación
Nuevo router de consulta paciente y método getPatient en reviews/service. app.ts monta /api/documents/:id/review. Se amplía la ruta permitida de AuthApi, restringiendo review a GET. Nuevo RevisionPacientePanel integrado en ProcesamientoPanel; consulta explícita, solo lectura, copia revisada, observaciones y fecha; retiro de datos al actualizar o fallar.

Sin migraciones ni dependencias nuevas. La extracción IA original y las revisiones aprobadas son inmutables. El verificador existente se amplía para probar ausencia de revisión, copia aprobada, aislamiento entre pacientes y conservación de acceso propio al revocar la asignación.

## Validación
Compilación TypeScript y 276 pruebas backend en 33 suites aprobadas, incluyendo consulta/aislamiento y regresión. Flutter no disponible en este entorno; seis pruebas nuevas preparadas para ejecución del usuario, sin afirmar aprobación local. PostgreSQL externo también requiere ejecutar el verificador en Windows. Véase docs/consulta-revision-paciente.md.

## Reversión
Revertir el commit de esta fase y reiniciar backend/Flutter. No hay cambio de esquema ni datos persistentes que deshacer.
