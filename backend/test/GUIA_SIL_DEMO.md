# Vitalia Health — laboratorio de demostración (Windows/Docker)

Esta guía solo aplica a `vitalia-postgres-sil-persistent` y la red `vitalia-fase7-test-net`. No ejecutar con contenedores de producción ni con la base principal de Vitalia.

## Roles implementados

- **Operador de laboratorio** (`operador_laboratorio`): búsqueda de paciente existente por correo, catálogo, órdenes con una o varias prestaciones, recepción de muestras, registro de resultados y revisión interna desde **Por revisar** con la cuenta autorizada de la demo.
- **Administrador** (`administrador`): acceso a pantalla administrativa separada, sin autorización de escritura en rutas SIL. Gestión de usuarios aún pendiente.
- **Paciente**: sin acceso a rutas SIL de trabajo interno.

## Prestaciones en catálogo

Hemograma (5 analitos sintéticos), perfil lipídico (4), glicemia (1), HbA1c (1), perfil renal (3) y perfil hepático (5). La base contiene plantillas sintéticas, **no** intervalos clínicos universales. Una orden puede incluir varios exámenes; la recepción registra los tubos EDTA, suero o fluoruro que requiere cada prestación. La correspondencia es una simplificación académica y no sustituye protocolos clínicos.

## Accesos de demostración persistentes

**No guardar ninguna contraseña en Git, documentos compartidos ni código fuente.** La nueva API lee contraseñas configuradas localmente. Correos:
- Operador: `operador.sil@example.invalid`
- Administrador: `admin.sil@example.invalid`
- Paciente semilla: `paciente.sil@example.invalid`.

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

## Recepción de solicitudes médicas ficticias (migración 034)

**Nuevo módulo del operador: `Recibir solicitud`.** Esta es la entrada documental a nuestro flujo de órdenes, sin implementar admisión, caja, facturación ni toma real de muestras. Conservamos la opción `Nueva orden` para las pruebas manuales anteriores; en el flujo documental se recomienda `Recibir solicitud`.

1. El operador crea o consulta una **Ficha paciente DEMO**, vinculada a una cuenta ficticia `@example.invalid`. La cuenta usa correo/contraseña para autenticarse, pero la asociación clínica se decide mediante `patient_id` interno, identificador ficticio, nombres, apellidos y fecha de nacimiento. El correo **nunca** es prueba de identidad clínica.
2. El operador selecciona una **solicitud médica PDF ficticia** (máximo 2 MiB, con texto seleccionable) que contenga identificador `DEMO-...`, nombre/apellido y fecha de nacimiento idénticos a la ficha. `POST /api/sil/medical-requests/preview` lee el PDF mediante el parser existente, comprueba esos campos, propone códigos del catálogo mediante coincidencias textuales y **no escribe en PostgreSQL**.
3. Las sugerencias de prestaciones **no utilizan IA generativa**: esta etapa usa prelectura y normalización determinista. No adjudicarle a un LLM verificación de identidad ni de una orden firmada. PDF escaneado que necesite OCR, identidades ambiguas o datos incompatibles quedan **bloqueados**, sin comprobante de creación.
4. Con identidad cotejada, se entrega un comprobante efímero (10 minutos) enlazado a la cuenta del operador y `patient_id`. El profesional operador revisa manualmente **sucursal, profesional solicitante que figura en el documento (no se verifica matrícula ni firma), fecha, número de solicitud y prestaciones**.
5. Solo con una casilla de confirmación explícita, `POST /api/sil/medical-requests/confirm` crea **en una única transacción** la orden interna, las prestaciones, el PDF original, su SHA-256, la referencia documental, la sucursal y eventos de auditoría. Si la misma solicitud/documento se envía de nuevo, se bloquea por paciente + huella SHA-256. Si falla la operación, la transacción se revierte.
6. La orden queda en `registered`; el operador sigue con las muestras declaradas y resultados. Los PDF de solicitudes son **internos**; no se publican en `Mis informes` del paciente. El operador puede consultar el documento original mediante `GET /api/sil/orders/:id/medical-request/file`, que deja una entrada de auditoría. Administrador y paciente no pueden abrirlo.
7. Se conserva la posibilidad técnica de registrar órdenes **manuales ficticias** por compatibilidad con pruebas previas, sin fingir una solicitud médica. Una solicitud registrada se identifica en los detalles y auditoría.

**Seguridad y alcance:** estos campos no sustituyen verificación profesional real de identidad, legitimidad de prescripción, firma, credenciales sanitarias o manejo de datos sensibles; están diseñados exclusivamente para el entorno aislado del laboratorio de pruebas. No introducir RUN ni documentos de pacientes reales. No se crean cuentas de paciente desde PDFs. Sin vínculo comprobable no hay orden nueva.

**Despliegue local:** detener SOLO `vitalia-sil-demo`, ejecutar migración `034_sil_medical_requests_demo` con el migrador existente contra **`vitalia_dev` de `vitalia-postgres-sil-persistent`**, verificarla, ejecutar las pruebas PostgreSQL, luego reiniciar únicamente la API SIL y Flutter. Conservar `vitalia_sil_test_data`, las contraseñas permanentes y los contenedores de la aplicación principal. No introducir SQL directamente en producción.

## Resultados mediante PDF e IA: borrador + corrección manual

**Cambio de alcance del operador:** `Automático` significa **seleccionar un PDF de resultados ficticios y ejecutar extracción de IA**, NO pulsar un simulador para inventar valores. El simulador de plantillas sigue disponible únicamente para pruebas técnicas antiguas por API, pero se retiró de la interfaz del operador. `Muestras` registra por separado la **recepción física declarada de los tubos**; un PDF nunca prueba que se haya recibido una muestra.

Desde `Resultados` de una orden que tenga todos los tubos requeridos en estado `sampled`, el operador puede:
1. Seleccionar un PDF de demostración de hasta 2 MiB que incluya el identificador `DEMO-...` correspondiente a la ficha del paciente.
2. Pulsar `Analizar archivo con IA`. El backend verifica el estado de la orden y la identidad sintética, extrae el texto mediante el lector PDF preexistente y llama al extractor de Ollama. El resultado **NO se almacena** todavía.
3. Revisar los valores precargados. Si la IA no identifica un analito, produce valores/ unidades ambiguas, informa incidencias, no encuentra el valor junto al nombre en la fuente, o el PDF necesita OCR, Vitalia lo marca como **pendiente de revisión manual**.
4. Corregir/ingresar los valores faltantes, revisar cada cifra contra el PDF original y marcar el control de confirmación.
5. Pulsar `Registrar resultados`. Se reutiliza exactamente la validación y transacción del ingreso manual; el resultado pasa a `results_recorded` y entra a la revisión profesional. La auditoría marca `assistedImport:true` solo si existe un comprobante temporal de extracción IA vinculado a la cuenta y orden, válido por 10 minutos. El registro conserva como responsable al operador. La IA no valida clínicamente ni publica.
6. Si la IA falla o no existe texto legible, la captura manual permanece disponible. Si falla la identidad del PDF, hay que descartarlo antes de registrar manualmente. No usar datos clínicos reales.

Ruta API para la vista previa: `POST /api/sil/orders/:id/results/preview` con `Content-Type: application/pdf` y token del operador; devuelve `{preview:{state,items,warnings,confirmed:false,previewToken}}`. El servidor **no guarda ni publica el archivo en esta ruta**. Ruta de guardado: `POST /api/sil/orders/:id/results`, con todos los resultados revisados y, si corresponde, `previewToken`. No hay migración nueva.

**Dependencia Ollama:** el contenedor `vitalia-sil-demo` necesita conectividad hacia el servicio local de Ollama. Para `VITALIA_RUNTIME=container` y `VITALIA_OLLAMA_SERVICE=ollama`, usar una **red de Docker separada** compartida exclusivamente por el contenedor demo y Ollama. No conectar la aplicación principal ni PostgreSQL de producción a una red nueva sin revisión. Sin conexión a Ollama, la ruta devuelve `analysis_unavailable` y permite continuar manualmente; nunca simula una extracción como si fuera IA.

Pruebas de aceptación obligatorias: acceso únicamente de operador, informe de identidad distinta rechazado, falta de muestra rechazada, PDF OCR informa limitación, errores o duplicados de analitos quedan sin precargar, ninguna consulta de previsualización escribe en PostgreSQL, y el guardado requiere confirmación y pasa a la bandeja Por revisar. Estas pruebas no prueban uso clínico real.

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

No iniciar `vitalia-sil-demo` actualizado hasta ejecutar la migración 033 sobre **`vitalia_dev` de `vitalia-postgres-sil-persistent`**. Conservar el volumen `vitalia_sil_test_data` y las contraseñas ya configuradas; ninguna actualización del código requiere regenerarlas. La API principal y `vitalia-postgres-1` quedan fuera de esta prueba.

## Publicación postanalítica de PDF externo (MVP aislado)

La migración **`032_sil_audit_download`** corrige la restricción de auditoría para admitir el evento `external_report_downloaded` al descargar el PDF desde el portal del paciente. Es incremental: no elimina ni reescribe informes existentes. Debe aplicarse después de `031` en `vitalia_dev`, antes de la prueba de integración de PDF.

La migración **`031_sil_external_reports`** incorpora un circuito separado para informes PDF previamente autorizados **por un laboratorio externo**, sin utilizar el simulador de analitos. Una orden nueva se asocia con un paciente registrado y el operador accede a **Informes PDF**: selecciona un archivo de prueba de hasta 2 MiB, indica el laboratorio emisor, la referencia y fecha de la autorización externa y declara haber comprobado esa autorización y la asociación con el paciente. Tras un paso separado de confirmación, el PDF se publica exclusivamente en el acceso del paciente correspondiente.

- **Seguridad:** el listado y la descarga verifican sesión `paciente`, propiedad del documento, publicación previa y hash SHA-256. El servidor entrega el PDF como adjunto, `no-store` y `nosniff`. Las operaciones quedan auditadas.
- **Límites:** los bytes del PDF se guardan en PostgreSQL **solo en el entorno de demostración aislado**; no hay verificación criptográfica de una firma externa, escaneo antimalware, integración con un repositorio clínico, análisis real de exámenes ni autorización clínica realizada por Vitalia. Usar exclusivamente PDF sintéticos; para producción se requiere almacenamiento privado externo, revisión de seguridad y acuerdos con el laboratorio.
- **Notificación:** publicar permite ver el informe al acceder al portal, **no envía mensajes ni correos todavía**.
- **Aislamiento:** las rutas de carga y lectura de PDF del SIL devuelven acceso denegado cuando `VITALIA_SIL_DEMO` no está activado.

### Contraseña del paciente de pruebas

El archivo `$HOME\.vitalia-sil-demo.env` debe incorporar la clave permanente del paciente, conservando las del operador y el administrador:

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

## Revisión interna desde el operador

Entra a `http://localhost:5173/#/laboratorio` con `operador.sil@example.invalid` y abre **Por revisar**. La cuenta autorizada puede aprobar la revisión interna o devolver la orden con un motivo de al menos diez caracteres. Los valores anteriores quedan registrados en auditoría si la orden se corrige. La publicación al paciente usa su flujo de PDF autorizado.

La migración `035_sil_retire_validator_role` desactiva los permisos del antiguo modo de validación y cierra sus sesiones. Las cuentas históricas y la autoría de las decisiones se conservan. El enlace anterior `/#/validacion` abre el acceso del laboratorio. La demo requiere las contraseñas del operador, administrador y paciente.

La estación de trabajo del operador ahora ofrece navegación por Resumen, Órdenes, Nueva orden, Muestras y Resultados. El resumen lee métricas agregadas de PostgreSQL; la tabla permite buscar correo/número VH-000001/UUID, filtrar por estado y avanzar por páginas de 20 registros.

La migración `028_sil_order_numbers` añade un correlativo de orden legible y conserva los UUID como claves internas.

La migración **`029_sil_traceability`** separa los tubos EDTA, suero y fluoruro por orden, mantiene registros anteriores como `historical`, agrega la cuenta responsable de la recepción, el origen del resultado y eventos de auditoría de las operaciones nuevas. No borra muestras ni resultados anteriores. Una orden nueva con hemograma y perfil lipídico necesita un tubo EDTA y uno de suero. El registro manual exige todos los analitos de las prestaciones solicitadas y toma las unidades del catálogo; no habilita validación clínica.

**No iniciar el backend actualizado antes de aplicar la migración 033 exclusivamente en `vitalia_dev`.** No ejecutar migraciones sobre la base principal.

Las contraseñas se conservan en el archivo local. Al reiniciar Docker, las cuentas se mantienen en PostgreSQL y el script de inicio reutiliza los correos. Si se reconstruye la base aislada, se regeneran las mismas credenciales desde el archivo local, siempre que se vuelvan a aplicar las migraciones.

## Preparación (con PostgreSQL de pruebas encendido)

Desde la raíz del repositorio:

```powershell
git pull --ff-only
npm --prefix .\backend run build
npm --prefix .\backend test
```

**Detenerse si falla el compilador o las pruebas.** Para actualizar una demo existente, detén solo `vitalia-sil-demo`, deja PostgreSQL encendido y ejecuta el migrador hasta la versión 035 en `vitalia_dev`. Si el contenedor demo ya monta `backend\dist` y `backend\test`, vuelve a iniciarlo con `docker start vitalia-sil-demo` cuando la migración termine correctamente.

```powershell
$distPath = (Resolve-Path ".\backend\dist").Path
$migrationsPath = (Resolve-Path ".\backend\database\migrations").Path
try {
    $env:PGPASSWORD = (docker exec vitalia-postgres-sil-persistent printenv POSTGRES_PASSWORD).Trim()
    docker run --rm --network vitalia-fase7-test-net `
      --mount "type=bind,source=$distPath,target=/app/dist,readonly" `
      --mount "type=bind,source=$migrationsPath,target=/app/database/migrations,readonly" `
      --env PGPASSWORD --env PGHOST=postgres --env PGPORT=5432 `
      --env PGDATABASE=vitalia_dev --env PGUSER=vitalia `
      --env VITALIA_RUNTIME=container --entrypoint node `
      vitalia-backend:local dist/database/migrate-all.js
    if ($LASTEXITCODE -ne 0) { throw "Fallaron las migraciones del SIL." }
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

No eliminar `vitalia-postgres-sil-persistent`, su base de datos ni las redes. Crear el nuevo contenedor con la red de acceso primero, unirlo a la red interna antes de arrancarlo:

```powershell
$testPath = (Resolve-Path ".\backend\test").Path
$distPath = (Resolve-Path ".\backend\dist").Path
$secretPath = Join-Path $HOME ".vitalia-sil-demo.env"
try {
    $env:PGPASSWORD = (docker exec vitalia-postgres-sil-persistent printenv POSTGRES_PASSWORD).Trim()
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

Entrar a `http://localhost:5173/#/laboratorio` con el operador estable; la ruta `/#/administracion` sigue destinada al administrador. El paciente semilla puede buscarse por correo, sin UUID. No presentar datos sintéticos como informes clínicos publicados.


## Interfaz postanalítica renovada — directorio, permisos y accesibilidad

Esta iteración mejora la presentación **sin ampliar el alcance SIL**: no procesa
muestras reales, no verifica firmas ni valida clínicamente resultados. La
migración 035 ya retiró el rol operativo de validador; se conserva el historial
de acciones. La revisión interna se realiza desde **Revisión interna** con la
cuenta de operador DEMO autorizada. Aprobar una revisión **no publica** un informe.

### Directorio de pacientes ficticios

- Ruta para el operador: `GET /api/sil/patients/list`, limitada a
  `VITALIA_SIL_DEMO=YES`; requiere rol `operador_laboratorio`.
- Parámetros: `limit` (1–50, predeterminado 20), `offset` (0–10000),
  `search` (máx. 100), `profile` (all/complete/incomplete),
  `orders` (all/with/without), `sex` (all/female/male/not_specified) y
  `sort` (name/recent). Respuesta: `patients,total,limit,offset`.
- El servidor devuelve solo cuentas `@example.invalid` de rol paciente.
  El filtro busca correo, nombre, apellidos e identificador sintético
  mediante valores SQL parametrizados. No retorna teléfono, PDF ni resultados.
- Solo se cargan 20 filas por página: con 100 pacientes, hay cinco páginas.
  En escritorio, la tabla ocupa todo el ancho hasta abrir la ficha; al
  seleccionarla se presenta el detalle al lado. En celular, lista y ficha se
  alternan, sin perder filtros.
- Acciones visibles: `Ficha`, `Solicitud` (requiere ficha completa) y
  `Órdenes` (si hay órdenes). Cambiar de paciente antes de una solicitud
  descarta la prelectura y las confirmaciones anteriores.
- No se crean cuentas desde el directorio ni se exportan datos. El portal de
  pacientes mantiene el registro separado. La página no admite datos reales.

### Verificación y actualización del entorno aislado

Desde la raíz, **sin ejecutar migraciones ni cambiar volúmenes**:

```powershell
git pull --ff-only
npm --prefix backend run check
npm --prefix backend test
cd apps\vitalia
flutter analyze
flutter test
flutter build web
```

Si todas las pruebas son correctas, regresar a la raíz, confirmar que el
contenedor existente monta `/app/dist` desde este repositorio y reiniciar
**solo** `vitalia-sil-demo` para que lea el backend TypeScript compilado:

```powershell
cd ..\..
docker inspect vitalia-sil-demo --format '{{range .Mounts}}{{println .Destination}}{{end}}'
docker restart vitalia-sil-demo
Invoke-RestMethod http://127.0.0.1:3101/api/health
docker exec vitalia-sil-demo node test/sil-patients-directory-smoke.cjs
```

Si no hay montaje `/app/dist` o falla el servidor de pruebas, **no** recrear
contenedores a ciegas: utilizar la sección de despliegue aislado de esta guía.
Nunca ejecutar `docker compose down -v`, `docker rm -v` contra la base
persistente, ni reconstruir la API principal solo para probar la UI.

Al abrir Flutter, apuntar específicamente a la demo SIL:

```powershell
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3101
```

Pruebas automatizadas añadidas: filtros y control de acceso del directorio,
parámetros SQL, paginación y navegación en móvil con 100 cuentas sintéticas
**simuladas en el test**. Esas 100 cuentas no se insertan en PostgreSQL; la
instalación conserva los pacientes existentes.
