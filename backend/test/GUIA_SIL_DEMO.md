# Vitalia Health — laboratorio de demostración (Windows/Docker)

Esta guía solo aplica a `vitalia-postgres-test` y la red `vitalia-fase7-test-net`. No ejecutar con contenedores de producción ni con la base principal de Vitalia.

## Roles implementados

- **Operador de laboratorio** (`operador_laboratorio`): búsqueda de paciente existente por correo, catálogo, órdenes con una o varias prestaciones, recepción de muestra y registro de resultados de demostración.
- **Administrador** (`administrador`): acceso a pantalla administrativa separada, sin autorización de escritura en rutas SIL. Gestión de usuarios aún pendiente.
- **Responsable de validación** (`validador_laboratorio`): acceso exclusivo a la bandeja de revisión, aprobación interna o devolución motivada; no puede operar muestras ni publicar resultados.
- **Paciente**: sin acceso a rutas SIL de trabajo interno.

## Prestaciones en catálogo

Hemograma (5 analitos sintéticos), perfil lipídico (4), glicemia (1), HbA1c (1), perfil renal (3) y perfil hepático (5). La base contiene plantillas sintéticas, **no** intervalos clínicos universales. Una orden puede incluir varios exámenes; la recepción registra los tubos EDTA, suero o fluoruro que requiere cada prestación. La correspondencia es una simplificación académica y no sustituye protocolos clínicos.

## Accesos de demostración persistentes

**No guardar ninguna contraseña en Git, documentos compartidos ni código fuente.** La nueva API lee contraseñas configuradas localmente. Correos:
- Operador: `operador.sil@example.invalid`
- Administrador: `admin.sil@example.invalid`
- Validador: `validador.sil@example.invalid`
- Paciente semilla: `paciente.sil@example.invalid` (solo para crear órdenes; todavía no se expone acceso de paciente).

Generar una vez el archivo `$HOME\.vitalia-sil-demo.env` (fuera del repositorio) mediante PowerShell:

```powershell
$secretPath = Join-Path $HOME ".vitalia-sil-demo.env"
if (-not (Test-Path $secretPath)) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes1 = New-Object byte[] 24
        $bytes2 = New-Object byte[] 24
        $rng.GetBytes($bytes1)
        $rng.GetBytes($bytes2)
        $pwOperator = [Convert]::ToBase64String($bytes1)
        $pwAdmin = [Convert]::ToBase64String($bytes2)
    } finally { $rng.Dispose() }
    @(
        "VITALIA_SIL_OPERATOR_PASSWORD=$pwOperator"
        "VITALIA_SIL_ADMIN_PASSWORD=$pwAdmin"
    ) | Set-Content -Encoding ASCII $secretPath
}
# Ver las contraseñas SOLO en tu PC; no pegarlas en chats.
# Get-Content $secretPath
```

## IA educativa en el portal del paciente (SIL demo)

El portal **Mis informes** muestra un botón `Consultar con IA educativa` por cada informe publicado. La conversación está restringida a la cuenta propietaria del PDF mediante sesión, identificador de informe y estado publicado.

**Alcance actual:** el asistente utiliza **los nombres de las prestaciones registradas en la orden**, no analiza todavía los bytes ni los valores del PDF. Responde preguntas generales sobre conceptos como *glicemia* o *hemoglobina glicosilada (HbA1c)* aprovechando el motor educativo y su biblioteca de definiciones. Ante preguntas por cifras, diagnóstico o tratamiento, advierte que no cuenta con resultados numéricos verificados y remite al documento original. **No afirmar que la IA leyó los valores del informe.**

La ruta `POST /api/sil/patient/reports/:id/chat` solo funciona para cuentas paciente en el modo aislado `VITALIA_SIL_DEMO=YES`. No acepta IDs de paciente suministrados por el cliente. Hasta 12 consultas al modelo por informe cada 15 minutos y una consulta concurrente por paciente/informe. No se almacena el historial de preguntas en PostgreSQL; la interfaz mantiene solo la conversación abierta.

- Las preguntas conceptuales sencillas admitidas por la biblioteca funcionan mediante la ruta de evidencia del asistente **incluso sin Ollama**. Para consultas abiertas que requieren generación, debe existir un servicio Ollama local accesible **desde el contenedor demo**; si no, el backend responde `503 ASSISTANT_UNAVAILABLE` sin inventar contenido.
- La IA existente conserva sus reglas de seguridad: no diagnósticos, no tratamientos, no conclusiones clínicas ni cifras generadas.
- **Siguiente fase**: lectura y extracción real del PDF, contrastada y aprobada por personal autorizado, antes de habilitar consultas de resultados numéricos. El hecho de que el PDF esté publicado no significa que sus cifras hayan sido extraídas y verificadas por la IA.
- No usar exámenes de pacientes reales en este entorno.

## Catálogo laboratorio/sucursales y ficha sintética (migración 033)

La migración **`033_sil_branches_patient_demo`** añade un catálogo de laboratorio ficticio **Laboratorio Pérez** y tres sucursales de demostración: Vitacura, Las Condes y Providencia. La lista se consulta por API, no se envía una razón social arbitraria desde el navegador. Es un *ejemplo de una sola empresa*, no un sistema multiempresa ni un módulo de sucursales reales.

La estación del operador incorpora **Ficha paciente DEMO** y **Informes PDF**. La ficha solo admite cuentas `@example.invalid`, un identificador sintético `DEMO-...`, nombres/fecha/sexo y un teléfono **inventados**. No almacenes RUN, teléfonos ni datos de pacientes reales en este entorno. La ficha queda asociada a la cuenta de paciente existente; no crea cuentas nuevas. Una vez existe un informe asociado, la ficha se inmoviliza para evitar reasignar documentos mediante cambios de identidad.

En la carga del PDF se elige una sucursal y se consignan por separado:
- **Laboratorio**: del catálogo (origen organizacional).
- **Sucursal**: centro de procedencia de la orden/informe (catálogo ficticio).
- **Profesional indicado en el informe**: texto transcrito; **no equivale a verificar su firma o habilitación**.
- **N.º de informe/referencia de autorización**: identificador documental, **no es el nombre del director técnico**.
- **Identificador de paciente leído manualmente del PDF**: debe coincidir con la ficha `DEMO-...`.

La coincidencia del identificador es una **comprobación manual**, no lectura automática OCR ni validación de firma. Si no coincide, el backend rechaza la incorporación; el PDF solo puede publicarse cuando la comprobación fue registrada. Antes de operar con datos reales harían falta aislamiento multiempresa, identificación y acceso seguros, OCR verificable con manejo de errores, seguridad adicional, almacenamiento externo, y diseño normativo.

No iniciar `vitalia-sil-demo` actualizado hasta ejecutar la migración 033 sobre **`vitalia_dev` de `vitalia-postgres-sil-persistent`**. Conservar el volumen `vitalia_sil_test_data` y las cuatro contraseñas ya configuradas; ninguna actualización del código requiere regenerarlas. La API principal y `vitalia-postgres-1` quedan fuera de esta prueba.

## Publicación postanalítica de PDF externo (MVP aislado)

La migración **`032_sil_audit_download`** corrige la restricción de auditoría para admitir el evento `external_report_downloaded` al descargar el PDF desde el portal del paciente. Es incremental: no elimina ni reescribe informes existentes. Debe aplicarse después de `031` en `vitalia_dev`, antes de la prueba de integración de PDF.

La migración **`031_sil_external_reports`** incorpora un circuito separado para informes PDF previamente autorizados **por un laboratorio externo**, sin utilizar el simulador de analitos. Una orden nueva se asocia con un paciente registrado y el operador accede a **Informes PDF**: selecciona un archivo de prueba de hasta 2 MiB, indica el laboratorio emisor, la referencia y fecha de la autorización externa y declara haber comprobado esa autorización y la asociación con el paciente. Tras un paso separado de confirmación, el PDF se publica exclusivamente en el acceso del paciente correspondiente.

- **Seguridad:** el listado y la descarga verifican sesión `paciente`, propiedad del documento, publicación previa y hash SHA-256. El servidor entrega el PDF como adjunto, `no-store` y `nosniff`. Las operaciones quedan auditadas.
- **Límites:** los bytes del PDF se guardan en PostgreSQL **solo en el entorno de demostración aislado**; no hay verificación criptográfica de una firma externa, escaneo antimalware, integración con un repositorio clínico, análisis real de exámenes ni autorización clínica realizada por Vitalia. Usar exclusivamente PDF sintéticos; para producción se requiere almacenamiento privado externo, revisión de seguridad y acuerdos con el laboratorio.
- **Notificación:** publicar permite ver el informe al acceder al portal, **no envía mensajes ni correos todavía**.
- **Aislamiento:** las rutas de carga y lectura de PDF del SIL devuelven acceso denegado cuando `VITALIA_SIL_DEMO` no está activado.

### Cuarta contraseña: paciente de pruebas

El archivo `$HOME\.vitalia-sil-demo.env` debe incorporar una cuarta clave permanente, **sin sustituir las tres existentes**:

```powershell
$secretPath = Join-Path $HOME ".vitalia-sil-demo.env"
if (-not (Test-Path $secretPath)) { throw "No existe el archivo local de contraseñas." }
if (-not (Select-String -Path $secretPath -Pattern '^VITALIA_SIL_PATIENT_PASSWORD=' -Quiet)) {
    $bytes = New-Object byte[] 24
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
        $patientSecret = [Convert]::ToBase64String($bytes)
        Add-Content -Path $secretPath -Encoding ASCII -Value ("VITALIA_SIL_PATIENT_PASSWORD=" + $patientSecret)
    } finally {
        $rng.Dispose()
        Remove-Variable patientSecret -ErrorAction SilentlyContinue
    }
}
```

El script de inicio reutiliza `paciente.sil@example.invalid` y actualiza solamente el hash para la nueva clave persistente. La nueva variable requiere **recrear exclusivamente** `vitalia-sil-demo` (no basta `docker start`). No revelar contraseñas por chat ni guardarlas en Git.

Para abrir el portal aislado del paciente, lanzar Flutter con ambos parámetros:
```powershell
flutter run -d edge --web-hostname localhost --web-port 5173 `
  --dart-define=VITALIA_API_URL=http://127.0.0.1:3101 `
  --dart-define=VITALIA_SIL_DEMO_MODE=true
```
Entrar a `http://localhost:5173/#/informes` con `paciente.sil@example.invalid` y su clave del archivo local. Esta modalidad no reemplaza ni modifica el portal de documentos original; es una pantalla de demostración separada.

## Contraseña permanente del validador

El archivo de secretos que ya existe **no se debe reemplazar**. Solo agrega una tercera contraseña si falta, sin mostrarla en consola ni en chats:

```powershell
$secretPath = Join-Path $HOME ".vitalia-sil-demo.env"
if (-not (Test-Path $secretPath)) { throw "Falta el archivo de secretos del SIL." }
if (-not (Select-String -Path $secretPath -Pattern '^VITALIA_SIL_VALIDATOR_PASSWORD=' -Quiet)) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object byte[] 24
        $rng.GetBytes($bytes)
        $validatorSecret = [Convert]::ToBase64String($bytes)
    } finally { $rng.Dispose() }
    Add-Content -Encoding ASCII -Path $secretPath -Value ("VITALIA_SIL_VALIDATOR_PASSWORD=" + $validatorSecret)
    Remove-Variable validatorSecret -ErrorAction SilentlyContinue
}
```

**Importante:** Docker fija las variables del `--env-file` al crear el contenedor. Para introducir la nueva variable se debe detener y recrear **solo** `vitalia-sil-demo` usando la sección de recreación. Reiniciarlo con `docker start` no carga la nueva contraseña.

### Revisión interna con retorno al operador

La migración `030_sil_review_workflow` habilita `review_approved` y `review_rejected`, agrega eventos de auditoría y mantiene cerrada la publicación. El validador revisa órdenes con resultados completos, aprueba la revisión interna o devuelve la orden con motivo de al menos diez caracteres. El operador puede corregir todos los parámetros de una orden devuelta; los valores anteriores quedan preservados en el evento de auditoría `results_corrected`. Una revisión aprobada no se puede editar desde el SIL. Ninguna decisión implica validación clínica de resultados reales.

Acceso del validador: `http://localhost:5173/#/validacion`. El rol requiere contraseña separada, guardada en el archivo local. 

La estación de trabajo del operador ahora ofrece navegación por Resumen, Órdenes, Nueva orden, Muestras y Resultados. El resumen lee métricas agregadas de PostgreSQL; la tabla permite buscar correo/número VH-000001/UUID, filtrar por estado y avanzar por páginas de 20 registros.

La migración `028_sil_order_numbers` añade un correlativo de orden legible y conserva los UUID como claves internas.

La migración **`029_sil_traceability`** separa los tubos EDTA, suero y fluoruro por orden, mantiene registros anteriores como `historical`, agrega la cuenta responsable de la recepción, el origen del resultado y eventos de auditoría de las operaciones nuevas. No borra muestras ni resultados anteriores. Una orden nueva con hemograma y perfil lipídico necesita un tubo EDTA y uno de suero. El registro manual exige todos los analitos de las prestaciones solicitadas y toma las unidades del catálogo; no habilita validación clínica.

**No iniciar el backend actualizado antes de aplicar la migración 033 exclusivamente en `vitalia_dev`.** No ejecutar migraciones sobre la base principal.

Las contraseñas se conservan en el archivo local. Al reiniciar Docker, las cuentas se mantienen en PostgreSQL y el script de inicio reutiliza los correos. Si se reconstruye la base aislada, se regeneran las mismas credenciales desde el archivo local, siempre que se vuelvan a aplicar las migraciones.

## Preparación (con PostgreSQL de pruebas encendido)

Desde la raíz del repositorio:

```powershell
git pull --ff-only origin feature/sil-simulador-analizador
npm --prefix .\backend run build
npm --prefix .\backend test
```

**Detenerse si falla el compilador o las pruebas.** Después aplicar todas las migraciones, incluidas `027_sil_catalog`, `028_sil_order_numbers`, `029_sil_traceability`, `030_sil_review_workflow`, `031_sil_external_reports` y `032_sil_audit_download`, en `vitalia_dev` usando la misma red Docker aislada. No se debe cambiar `PGDATABASE` por `vitalia`.

```powershell
$distPath = (Resolve-Path ".\backend\dist").Path
$migrationsPath = (Resolve-Path ".\backend\database\migrations").Path
try {
    $env:PGPASSWORD = (docker exec vitalia-postgres-test printenv POSTGRES_PASSWORD).Trim()
    docker run --rm --network vitalia-fase7-test-net `
      --mount "type=bind,source=$distPath,target=/app/dist,readonly" `
      --mount "type=bind,source=$migrationsPath,target=/app/database/migrations,readonly" `
      --env PGPASSWORD --env PGHOST=postgres --env PGPORT=5432 `
      --env PGDATABASE=vitalia_dev --env PGUSER=vitalia `
      --env VITALIA_RUNTIME=container --entrypoint node `
      vitalia-backend:local dist/database/migrate-all.js
} finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
```

## Recreación solo del contenedor SIL (después de actualizar el script)

Si existe `vitalia-sil-demo`, detenerlo y revisar sus registros. El script antiguo borra sus cuentas temporales al detenerse; el nuevo script no borra las cuentas persistentes.

```powershell
docker stop --timeout 30 vitalia-sil-demo
docker logs --tail 5 vitalia-sil-demo
docker rm vitalia-sil-demo
```

No eliminar `vitalia-postgres-test`, su base de datos ni las redes. Crear el nuevo contenedor con la red de acceso primero, unirlo a la red interna antes de arrancarlo:

```powershell
$testPath = (Resolve-Path ".\backend\test").Path
$distPath = (Resolve-Path ".\backend\dist").Path
$secretPath = Join-Path $HOME ".vitalia-sil-demo.env"
try {
    $env:PGPASSWORD = (docker exec vitalia-postgres-test printenv POSTGRES_PASSWORD).Trim()
    docker create --name vitalia-sil-demo `
      --network vitalia-sil-demo-access `
      --publish "127.0.0.1:3101:3000" `
      --mount "type=bind,source=$testPath,target=/app/test,readonly" `
      --mount "type=bind,source=$distPath,target=/app/dist,readonly" `
      --env-file $secretPath --env PGPASSWORD `
      --env PGHOST=postgres --env PGDATABASE=vitalia_dev `
      --env PGUSER=vitalia --env VITALIA_SIL_DEMO=YES `
      --entrypoint node vitalia-backend:local test/sil-demo-local.cjs
    if ($LASTEXITCODE -ne 0) { throw "No se pudo crear el contenedor" }
    docker network connect vitalia-fase7-test-net vitalia-sil-demo
    if ($LASTEXITCODE -ne 0) { throw "No se pudo unir la red de pruebas" }
    docker start vitalia-sil-demo
    if ($LASTEXITCODE -ne 0) { throw "No se pudo iniciar SIL" }
} finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
docker port vitalia-sil-demo
Invoke-RestMethod http://127.0.0.1:3101/api/health
docker logs --tail 8 vitalia-sil-demo
```

El script solo imprime correos e identificador del paciente, nunca las contraseñas. El puerto 3101 se publica en loopback; PostgreSQL sigue accesible solo por su red interna.

## Flutter

```powershell
cd apps\vitalia
$env:Path = "C:\src\flutter\bin;$env:Path"
flutter analyze
flutter test
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3101
```

Entrar a `http://localhost:5173/#/laboratorio` con el operador estable; la ruta `/#/administracion` sigue destinada al administrador. La ruta `/#/validacion` corresponde al validador. El paciente semilla puede buscarse por correo, sin UUID. No presentar datos sintéticos como informes clínicos publicados.
