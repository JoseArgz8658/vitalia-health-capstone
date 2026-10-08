# Asignaciones de pacientes a profesionales

## Alcance

El administrador activa, desactiva y reactiva relaciones entre cuentas existentes de paciente y profesional usando sus correos exactos. Cada profesional consulta solamente sus pacientes con asignación activa. No se muestran exámenes ni resultados en esta etapa y la asignación no aprueba extracciones ni acredita identidad profesional.

Se permite más de un profesional por paciente y más de un paciente por profesional. Un mismo par tiene una sola fila: reactivar conserva su ID y creación original. Las cuentas no cambian de rol.

## Migración y verificación Windows

Detén backend y Flutter con Ctrl+C. Desde la raíz del repositorio:

```powershell
git fetch origin
git switch --track origin/fase-5/asignaciones-pacientes
cd backend
npm test
node --env-file=.env dist/database/migrate-patient-assignments.js
node --env-file=.env dist/database/verify-patient-assignments.js
$LASTEXITCODE
npm start
```

Resultado esperado: «Migración de asignaciones aplicada» (o ya aplicada), «Asignaciones, aislamiento y auditoría correctos. Datos sintéticos revertidos» y código 0. La comprobación crea cuentas y relaciones ficticias dentro de una transacción y ejecuta ROLLBACK. No toca S3 ni IA. La migración 007 exige la 006 aplicada; no edites migraciones anteriores.

El backend ahora exige las tablas de asignaciones y auditoría al arrancar. Aplica 007 antes de npm start. No requiere instalar otras dependencias.

En otra terminal:

```powershell
cd C:\Users\josem\Documents\GitHub\vitalia-health-capstone-prueba\apps\vitalia
flutter pub get
flutter analyze
flutter test test/auth_api_test.dart test/acceso_integrado_test.dart test/documentos_api_test.dart test/paciente_documentos_test.dart test/procesamiento_test.dart test/asignaciones_test.dart
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

No compartir contraseñas ni datos reales. Verifica con cuentas ficticias locales.

## Prueba visual

1. Inicia sesión con el administrador que ya creaste. Verás «Asignaciones de pacientes».
2. Escribe el correo de tu paciente de prueba y el de la cuenta profesional (por ejemplo medico.vitalia@example.com si usaste la guía anterior). Pulsa «Asignar paciente».
3. Debe aparecer una asignación activa. Repetir la misma pareja conserva una sola fila.
4. Cierra sesión e ingresa como profesional. En «Mis pacientes» debe aparecer ese paciente. No hay controles de asignación ni acceso a exámenes todavía.
5. Vuelve al administrador y pulsa «Desactivar asignación». La fila permanece como inactiva.
6. Vuelve al profesional y pulsa «Actualizar lista»: el paciente debe desaparecer.
7. El administrador puede «Reactivar asignación»; al actualizar la lista profesional, el paciente vuelve a aparecer.

El botón Actualizar consulta el servidor; no hay actualización automática. En caso de error al refrescar se oculta la lista anterior para no presentarla como vigente. Otra cuenta profesional sin esa relación no debe ver el paciente. El historial del paciente mantiene su flujo actual.

## Contrato HTTP

Todas las rutas requieren token de sesión y devuelven Cache-Control: no-store. `GET /api/assignments?limit=20&offset=0` devuelve `{assignments: [...]}` al administrador (activas e inactivas) o `{patients: [...]}` al profesional (activas propias). Limit 1–20, offset 0–10000. No se acepta ID de profesional en la consulta: deriva de la sesión.

`POST /api/assignments` acepta solo `{patientEmail, professionalEmail}`. Administrador obligatorio. Responde 201 si activó/creó y 200 si ya estaba activa, con `{assignment}`. Las cuentas deben existir con los roles correspondientes.

`POST /api/assignments/{id}/deactivate` acepta `{}`. Administrador obligatorio. Desactivar repetidamente conserva el estado y no duplica la auditoría.

Sin sesión: 401. Paciente en estas rutas o profesional que intenta modificar: 403. Entrada o paginación inválida: 400. Cuenta con rol no adecuado, inexistente o asignación no disponible: 404. Error inesperado: 500 genérico. Nunca se devuelven hashes, contraseñas, claves S3 ni datos extraídos.

## Persistencia y trazabilidad

Migración 007 crea vitalia_patient_assignments y vitalia_assignment_audit. Cada relación conserva creador, último actor y fechas; cada cambio real genera evento activate/deactivate con administrador y fecha. Estado y auditoría se escriben en una transacción. El conflicto único por pareja evita duplicados y la activación/desactivación condicional evita eventos repetidos cuando no hay cambio.

La auditoría de asignaciones no reemplaza la futura auditoría de lectura o revisión de exámenes. No hay borrado, gestión de perfiles clínicos, verificación de habilitación profesional ni acceso clínico en esta fase. Desactivar elimina la relación de las consultas posteriores.

Pruebas backend aprobadas; Flutter y migración/verificación reales deben comprobarse en el equipo del usuario. El retiro del código no borra asignaciones ni eventos.
