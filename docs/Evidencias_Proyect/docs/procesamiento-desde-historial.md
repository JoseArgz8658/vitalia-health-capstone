# Solicitar procesamiento desde el historial

## Alcance

El paciente autenticado consulta el estado de cada documento propio y solicita un trabajo una sola vez. El botón registra una solicitud: la ejecución sigue siendo manual. No inicia Ollama desde Flutter ni procesa automáticamente al subir. No hay aprobación profesional ni consulta de resultados extraídos para el paciente.

Requiere migración 006 previamente aplicada. No incorpora migraciones ni dependencias. Al iniciar, el servidor comprueba también la existencia de la tabla de procesamiento.

## Contrato

`GET /api/documents/{id}/processing` devuelve HTTP 200 con `{processing: {status, approved: false, createdAt, startedAt, finishedAt}}`. Fechas ISO o null. `status` puede ser `not_requested`, `queued`, `processing`, `requires_review`, `rejected` o `failed`.

`POST /api/documents/{id}/processing` recibe `{}`. El servidor decide propietario, modelo y versión del prompt. Devuelve HTTP 202 si creó el trabajo y 200 si ya existía; ambos con el mismo contrato de estado. No reinicia ni sobrescribe trabajos existentes. La restricción única por documento de PostgreSQL evita duplicados concurrentes.

Sin sesión: 401. Rol distinto de paciente: 403. Documento ajeno, inexistente, no guardado o ID inválido: 404 sin distinguir el motivo. Campos extra o parámetros en POST: 400. Fallos inesperados: 500 genérico. Todas las respuestas de estas rutas tienen `Cache-Control: no-store`.

La API solo expone estado y tiempos. No devuelve texto OCR, respuesta del modelo, incidencias internas, claves S3 ni resultados aún sin revisión. No realiza descargas S3 ni llamadas a IA. La trazabilidad actual son los registros y fechas del trabajo; auditoría profesional pendiente.

## Comprobación Windows

Detén Flutter y el servidor con Ctrl+C en sus terminales. Desde la raíz del repositorio:

```powershell
git fetch origin
git switch --track origin/fase-5/solicitud-procesamiento
cd backend
npm test
npm start
```

Mantén el backend abierto. En otra terminal:

```powershell
cd C:\Users\josem\Documents\GitHub\vitalia-health-capstone-prueba\apps\vitalia
flutter pub get
flutter analyze
flutter test test/auth_api_test.dart test/documentos_api_test.dart test/paciente_documentos_test.dart test/procesamiento_test.dart
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

El origen web fijo es necesario para los permisos CORS del backend. Para Android, usa el comando habitual del emulador con `VITALIA_API_URL=http://10.0.2.2:3000`; el servidor debe tener la configuración HOST previamente usada para Android.

Inicia sesión como paciente. El PDF que ya procesaste debe mostrar «Extracción pendiente de revisión profesional», sin botón para repetir. La imagen rechazada debe mostrar que no se pudo extraer información.

Sube otro PDF ficticio con texto. Pulsa «Solicitar procesamiento»: debe mostrar «Procesamiento pendiente». «Actualizar estado» consulta de nuevo sin crear trabajo. Cerrar sesión y volver a entrar conserva el estado porque está en PostgreSQL.

En pgAdmin identifica el ID de ese nuevo documento ficticio. En una tercera terminal de backend, con Ollama abierto:

```powershell
$documento = 'UUID_DEL_NUEVO_DOCUMENTO_FICTICIO'
node --env-file=.env dist/database/process-document.js --document $documento
node --env-file=.env dist/database/process-document.js --document $documento --apply
$LASTEXITCODE
```

La consulta previa debe mostrar `queued`. Vuelve a Flutter y pulsa «Actualizar estado» en ese documento: debe mostrar revisión pendiente si la extracción terminó correctamente. No se aprueba automáticamente.

Comprueba con otra cuenta de paciente que su historial solo contiene sus documentos. Las pruebas HTTP verifican además acceso ajeno e inexistente sin reservar trabajo.

## Límites

No hay proceso automático ni recuperación/reintentos para trabajos interrumpidos o fallidos. Un trabajo por documento. No se añaden cuentas privilegiadas, asignaciones, revisión profesional ni diagnósticos. La extracción necesita cotejo con el original. La ejecución integral S3/PostgreSQL/Ollama y las pruebas Flutter deben verificarse en el equipo del usuario.
