# Vitalia Health — laboratorio de demostración (Windows/Docker)

Esta guía solo aplica a `vitalia-postgres-test` y la red `vitalia-fase7-test-net`. No ejecutar con contenedores de producción ni con la base principal de Vitalia.

## Roles implementados

- **Operador de laboratorio** (`operador_laboratorio`): búsqueda de paciente existente por correo, catálogo, órdenes con una o varias prestaciones, recepción de muestra y registro de resultados de demostración.
- **Administrador** (`administrador`): acceso a pantalla administrativa separada, sin autorización de escritura en rutas SIL. Gestión de usuarios aún pendiente.
- **Responsable de validación** (`validador_laboratorio`): rol reservado; acceso a consultas SIL, sin autorización de procesamiento ni validación implementada todavía.
- **Paciente**: sin acceso a rutas SIL de trabajo interno.

## Prestaciones en catálogo

Hemograma (5 analitos sintéticos), perfil lipídico (4), glicemia (1), HbA1c (1), perfil renal (3) y perfil hepático (5). La base contiene plantillas sintéticas, **no** intervalos clínicos universales. Una orden puede incluir varios exámenes; en esta fase, la recepción registra un único evento de muestra sanguínea por orden, no separa tubos físicos.

## Accesos de demostración persistentes

**No guardar ninguna contraseña en Git, documentos compartidos ni código fuente.** La nueva API lee contraseñas configuradas localmente. Correos:
- Operador: `operador.sil@example.invalid`
- Administrador: `admin.sil@example.invalid`
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

La estación de trabajo del operador ahora ofrece navegación por Resumen, Órdenes, Nueva orden, Muestras y Resultados. El resumen lee métricas agregadas de PostgreSQL; la tabla permite buscar correo/número VH-000001/UUID, filtrar por estado y avanzar por páginas de 20 registros.

La migración `028_sil_order_numbers` añade un correlativo de orden legible y conserva los UUID como claves internas. **No activar el backend actualizado hasta completar también la migración 028 exclusivamente en `vitalia_dev`.** No ejecutar migraciones sobre la base principal.

Las contraseñas se conservan en el archivo local. Al reiniciar Docker, las cuentas se mantienen en PostgreSQL y el script de inicio reutiliza los correos. Si se reconstruye la base aislada, se regeneran las mismas credenciales desde el archivo local, siempre que se vuelvan a aplicar las migraciones.

## Preparación (con PostgreSQL de pruebas encendido)

Desde la raíz del repositorio:

```powershell
git pull --ff-only origin feature/sil-simulador-analizador
npm --prefix .\backend run build
npm --prefix .\backend test
```

**Detenerse si falla el compilador o las pruebas.** Después aplicar todas las migraciones, incluidas `027_sil_catalog` y `028_sil_order_numbers`, en `vitalia_dev` usando la misma red Docker aislada. No se debe cambiar `PGDATABASE` por `vitalia`.

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

Entrar a `http://localhost:5173/#/laboratorio` con el operador estable; la ruta `/#/administracion` sigue destinada al administrador. El paciente semilla puede buscarse por correo, sin UUID. No presentar datos sintéticos como informes clínicos publicados.
