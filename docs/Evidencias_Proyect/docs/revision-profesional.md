# Revisión profesional y aprobación explícita

## Alcance

Un profesional con asignación activa coteja el PDF o imagen original, corrige la extracción y confirma el cotejo antes de aprobar. La aprobación crea una copia revisada separada, con profesional, fecha y observaciones. La salida original de IA, su texto, incidencias y approved false permanecen intactos.

Una revisión aprobada no se sobrescribe ni elimina: una revisión por procesamiento. Una rectificación posterior o anulación requiere otra etapa con versionado; no existe en este alcance. No se guardan borradores. Actualizar o cerrar el formulario descarta cambios no aprobados.

El paciente solo ve «Revisión profesional registrada». Mostrar datos revisados y explicarlos en palabras simples viene después. No hay diagnóstico ni tratamiento automático. El rol profesional de las cuentas locales no sustituye verificación de identidad/habilitación real.

## Windows: migración y verificación

Detén backend y Flutter con Ctrl+C. Desde la raíz:

```powershell
git fetch origin
git switch --track origin/fase-5/revision-profesional
cd backend
npm test
node --env-file=.env dist/database/migrate-professional-reviews.js
node --env-file=.env dist/database/verify-professional-reviews.js
$LASTEXITCODE
npm start
```

Espera migración de revisiones aplicada (o ya aplicada) y «Revisión, conservación del original, permisos e inmutabilidad correctos. Datos sintéticos revertidos», código 0. Migración 009 requiere 008 y el servidor requiere la nueva tabla al arrancar. No se agregan dependencias.

La verificación crea cuentas, relación, metadatos y extracción ficticios en una transacción PostgreSQL; comprueba revisión, conservación original, permisos, duplicado y protección contra UPDATE/DELETE mediante savepoints. Revierte todos sus datos al terminar. No lee S3 ni llama a IA. No se ejecutó contra la base del usuario desde el entorno de implementación.

En otra terminal:

```powershell
cd C:\Users\josem\Documents\GitHub\vitalia-health-capstone-prueba\apps\vitalia
flutter pub get
flutter analyze
flutter test test/auth_api_test.dart test/acceso_integrado_test.dart test/documentos_api_test.dart test/paciente_documentos_test.dart test/procesamiento_test.dart test/asignaciones_test.dart test/profesional_test.dart test/revision_profesional_test.dart
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

## Prueba visual con el PDF ficticio

1. Inicia sesión como profesional, verifica su asignación activa y abre Ver exámenes → Consultar extracción sobre el PDF ficticio 2 ya procesado.
2. Descarga y abre el original. Comprueba fecha 29-09-2026, Alfa 15,2 g/dL y referencia 14,0–16,0 g/dL; Beta 235.000 /µL y referencia 160.000–460.000 /µL.
3. Debajo de la extracción original aparece Revisión profesional. Los campos parten de la extracción guardada. No se altera el original mientras escribes.
4. Si la unidad Beta conserva el espacio inicial observado, puedes retirarlo manualmente en Unidad. No cambies cifras para esta prueba. La sustitución µ/μ solo debe hacerse tras cotejar el original; ninguna normalización es automática.
5. En Motivo de correcciones o datos ausentes escribe, por ejemplo, «Espacio inicial de unidad retirado tras cotejar el PDF ficticio» si realizaste ese cambio. Si no cambias nada y todos los campos están presentes, las observaciones pueden quedar vacías.
6. Marca «Confirmo que cotejé estos datos con el documento original». Solo entonces se habilita Aprobar y guardar revisión.
7. Tras aprobar debe aparecer «Revisión aprobada y registrada», profesional, fecha local y copia revisada. No habrá controles para sobrescribirla. Actualizar revisión conserva la aprobación. La sección original de IA sigue separada y sin modificaciones.
8. Inicia sesión como paciente y pulsa Actualizar estado en ese documento. Debe mostrar «Revisión profesional registrada». Aún no muestra la copia revisada ni explicación.

Un documento rechazado, sin trabajo, en cola o procesándose no permite aprobar. Si se desactiva la asignación antes de guardar, el servidor rechaza la aprobación y se retira la información de la consulta al recibir 403/404. Una aprobación ya guardada permanece en el historial aunque después se desactive la asignación.

Si una solicitud tarda, falla la conexión o devuelve conflicto, usa Actualizar revisión antes de repetir: pudo haberse guardado. No se permite sobrescribir el primer registro. No compartas documentos reales, observaciones sensibles ni contraseñas en las salidas de prueba.

## Validación de la copia revisada

Campos de texto hasta 500 caracteres; máximo 100 resultados; observaciones hasta 2000 caracteres; solicitud validada hasta 24 KiB. No hay truncamiento automático. Debe existir al menos un resultado. Fecha no nula: formato DD-MM-AAAA y calendario válido, incluyendo bisiestos.

Campo vacío se envía como null, sin convertirlo a cero. Los valores no vacíos conservan su texto, comas, separadores y espacios. Si corriges cualquier dato, agregas/quitas resultados o conservas algún campo null, exige observaciones no vacías. Los campos ausentes pueden conservarse explícitamente con explicación; una fecha imposible debe corregirse según el original o dejarse como ausente con explicación.

La confirmación es una declaración explícita del profesional; el sistema no puede comprobar por sí mismo que leyó el original. Aprobar la copia revisada no genera un diagnóstico ni aprueba automáticamente la respuesta de IA.

## Contrato HTTP

GET /api/professional/patients/{patientId}/documents/{documentId}/review devuelve processingId, originalExtraction, canReview y review nullable. Requiere rol profesional y relación activa con el paciente y documento stored. Registra la consulta como view_extraction en auditoría de acceso 008.

POST en la misma ruta acepta solo processingId, extraction, observations y confirmedOriginal true. Identidad del revisor y fechas vienen de sesión/servidor. El processingId debe corresponder al documento y tener estado requires_review con extracción disponible. Bloquea el procesamiento en la transacción antes de comprobar si ya existe revisión. Devuelve 201 con `{review}`.

Review incluye ID, processingId, reviewerId/reviewerEmail, extracción revisada, observaciones, reviewedAt y approved true. No contiene secretos, claves S3 ni respuesta cruda del modelo. Sesión ausente 401; otro rol 403; asignación/documento ausente o inactivo 404; datos/calendario/confirmación inválidos 400; revisión existente o procesamiento incompatible 409; errores inesperados 500 genérico. Todas las respuestas de estas rutas usan Cache-Control: no-store.

La consulta de estado del paciente conserva status y approved false de la extracción original y agrega reviewStatus approved/not_reviewed y reviewedAt nullable. No devuelve datos revisados, observaciones ni información de otros pacientes. Flutter interpreta la revisión registrada para su etiqueta sin alterar el estado técnico del procesamiento.

## Persistencia e inmutabilidad

009 crea vitalia_professional_reviews con vínculo a procesamiento/documento/paciente/asignación/revisor, copia original y revisada, observaciones, confirmación y fecha. Un índice único por procesamiento y bloqueo FOR UPDATE evitan aprobaciones concurrentes. Trigger rechaza UPDATE y DELETE de revisiones aprobadas. La relación activa se bloquea durante el guardado, sin transacción abierta mientras el humano edita.

El registro de revisión es la evidencia de aprobación. La auditoría 008 mantiene las consultas; no se reescribe la auditoría previa ni el procesamiento. La lectura de la revisión se restringe nuevamente a la asignación activa del solicitante.

Compilación TypeScript y 268 pruebas backend aprobadas en 32 suites. Flutter SDK no disponible aquí: pruebas de API/formulario, confirmación, conflicto, revocación y estado del paciente añadidas, pendientes en Windows. Migración/verificación real y flujo visual pendientes de comprobación local.
