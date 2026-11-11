# Prueba una restauracion del respaldo principal en PostgreSQL 16 aislado.
# NO se conecta a vitalia-postgres-1 ni a vitalia-postgres-sil-persistent.
# Usa Docker --network none, sin puertos, sin montajes del equipo y nombre aleatorio.
# Elimina solamente el contenedor temporal creado aqui y su volumen anonimo.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BackupFile,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-fA-F0-9]{64}$')]
  [string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'
$container = 'vitalia-restore-check-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteFile = '/tmp/vitalia-restore-check.dump'
$restoredDatabase = 'vitalia_restored'
$restoreUser = 'vitalia_restore'
$createdContainer = $false
$validated = $false
$migrationCount = ''

function Assert-DockerExit([string]$Step) {
  if ($LASTEXITCODE -ne 0) {
    throw "Fallo en $Step. No se modifico Vitalia principal."
  }
}

if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
  throw 'No se encontro el respaldo indicado.'
}

$backup = Get-Item -LiteralPath $BackupFile
if ($backup.Length -lt 1024) {
  throw 'El respaldo es demasiado pequeno.'
}
$localHash = (Get-FileHash -LiteralPath $backup.FullName -Algorithm SHA256).Hash
if ($localHash -ne $ExpectedSha256.ToUpperInvariant()) {
  throw 'SHA256 local diferente al esperado; restauracion cancelada.'
}

Write-Host 'SHA256 local comprobado. Iniciando PostgreSQL temporal sin red...'

try {
  # La imagen coincide con la usada por la base principal de compose.yaml.
  # Autenticacion trust solo dentro de un contenedor totalmente sin red.
  $containerId = & docker run --detach --pull=never --name $container --network none --env POSTGRES_USER=vitalia_restore --env POSTGRES_DB=vitalia_restored --env POSTGRES_HOST_AUTH_METHOD=trust postgres:16.15-bookworm
  Assert-DockerExit 'la creacion del contenedor temporal'
  if (-not ($containerId | Out-String).Trim()) {
    throw 'Docker no devolvio un ID para el contenedor.'
  }
  $createdContainer = $true

  $ready = $false
  for ($attempt = 0; $attempt -lt 45; $attempt++) {
    & docker exec $container pg_isready --username=$restoreUser --dbname=$restoredDatabase *> $null
    if ($LASTEXITCODE -eq 0) {
      $ready = $true
      break
    }
    Start-Sleep -Seconds 1
  }
  if (-not $ready) {
    throw 'La base temporal no pudo iniciar.'
  }

  # docker cp copia bytes, sin redireccionamiento binario desde PowerShell.
  $target = '{0}:{1}' -f $container, $remoteFile
  & docker cp $backup.FullName $target
  Assert-DockerExit 'la copia binaria al contenedor temporal'

  $remoteHashOutput = & docker exec $container sha256sum $remoteFile
  Assert-DockerExit 'el SHA256 dentro del contenedor'
  $hashMatch = [regex]::Match(($remoteHashOutput | Out-String).Trim(), '^([0-9a-fA-F]{64})\s+')
  if (-not $hashMatch.Success -or $hashMatch.Groups[1].Value.ToUpperInvariant() -ne $localHash) {
    throw 'Los bytes copiados no coinciden con el respaldo original.'
  }

  & docker exec $container pg_restore --list $remoteFile *> $null
  Assert-DockerExit 'el listado del respaldo'

  Write-Host 'Respaldo intacto. Restaurando en la base aislada...'
  # --single-transaction garantiza una restauracion atomica en la base TEMPORAL.
  & docker exec $container pg_restore --username=$restoreUser --dbname=$restoredDatabase --no-owner --no-privileges --single-transaction --exit-on-error $remoteFile
  Assert-DockerExit 'la restauracion completa'

  # Solo consultar metadatos. No mostrar filas con informacion personal.
  $schemaSql = "SELECT current_database() = 'vitalia_restored' AND to_regclass('public.vitalia_accounts') IS NOT NULL AND to_regclass('public.vitalia_sessions') IS NOT NULL AND to_regclass('public.vitalia_documents') IS NOT NULL AND to_regclass('public.vitalia_schema_migrations') IS NOT NULL;"
  $schemaCheck = & docker exec $container psql --username=$restoreUser --dbname=$restoredDatabase --no-psqlrc --tuples-only --no-align --set=ON_ERROR_STOP=1 --command $schemaSql
  Assert-DockerExit 'el esquema restaurado'
  if (($schemaCheck | Out-String).Trim() -ne 't') {
    throw 'Faltan tablas fundamentales en la restauracion aislada.'
  }

  $baselineSql = "SELECT EXISTS (SELECT 1 FROM public.vitalia_schema_migrations WHERE version = '012_preliminary_assistant');"
  $baselineCheck = & docker exec $container psql --username=$restoreUser --dbname=$restoredDatabase --no-psqlrc --tuples-only --no-align --set=ON_ERROR_STOP=1 --command $baselineSql
  Assert-DockerExit 'la migracion 012 historica'
  if (($baselineCheck | Out-String).Trim() -ne 't') {
    throw 'La migracion historica 012 falta en el respaldo.'
  }

  $countSql = 'SELECT count(*) FROM public.vitalia_schema_migrations;'
  $count = & docker exec $container psql --username=$restoreUser --dbname=$restoredDatabase --no-psqlrc --tuples-only --no-align --set=ON_ERROR_STOP=1 --command $countSql
  Assert-DockerExit 'el recuento de migraciones'
  $migrationCount = ($count | Out-String).Trim()
  if ($migrationCount -notmatch '^[0-9]+$' -or [int]$migrationCount -lt 12) {
    throw 'Recuento de migraciones inesperado.'
  }

  $validated = $true
}
finally {
  if ($createdContainer -and $container -match '^vitalia-restore-check-[a-f0-9]{12}$') {
    # El contenedor y volumen anonimo solo existen por este script.
    # No se opera sobre containers ni volumenes de Vitalia original.
    & docker rm --force --volumes $container *> $null
    if ($LASTEXITCODE -ne 0) {
      Write-Warning ('No se pudo retirar el contenedor temporal: ' + $container)
    }
  }
}

if ($validated) {
  Write-Host ''
  Write-Host 'RESTAURACION AISLADA VERIFICADA' -ForegroundColor Green
  Write-Host "Archivo: $($backup.Name)"
  Write-Host "SHA256: $localHash"
  Write-Host "Migraciones restauradas: $migrationCount"
  Write-Host 'Tablas principales y migracion 012: verificadas'
  Write-Host 'La base principal, DEMO y el archivo local no se modificaron.'
}
