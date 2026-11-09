# Ensayo migraciones en copia RESTAURADA en PostgreSQL 16 sin red.
# NO modifica ni conecta vitalia-postgres-1, DEMO o volumenes existentes.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BackupFile,
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-fA-F0-9]{64}$')]
  [string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'
$container = 'vitalia-migration-rehearsal-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteBackup = '/tmp/vitalia-main-pre-sil.dump'
$workdir = '/tmp/vitalia-migration-rehearsal'
$db = 'vitalia_restored'
$user = 'vitalia_restore'
$created = $false
$approved = $false

function Assert-Docker([string]$Step) {
  if ($LASTEXITCODE -ne 0) {
    throw "Fallo en $Step. No se modifico Vitalia principal."
  }
}

$absoluteBackup = (Resolve-Path -LiteralPath $BackupFile -ErrorAction Stop).Path
$backup = Get-Item -LiteralPath $absoluteBackup
if ($backup.Length -lt 1024) { throw 'El respaldo es anormalmente pequeno.' }
$localHash = (Get-FileHash -LiteralPath $absoluteBackup -Algorithm SHA256).Hash
if ($localHash -ne $ExpectedSha256.ToUpperInvariant()) {
  throw 'El SHA256 del respaldo difiere del esperado. Se cancela el ensayo.'
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sqlDir = Join-Path $root 'backend\database\migrations'
$runner = Join-Path $root 'backend\test\sil-main-migration-rehearsal.sh'
if (-not (Test-Path -LiteralPath (Join-Path $sqlDir '012_profiles_locations.sql') -PathType Leaf)) {
  throw 'Falta migracion 012 de perfiles en la rama actual.'
}
if (-not (Test-Path -LiteralPath (Join-Path $sqlDir '032_sil_audit_download.sql') -PathType Leaf)) {
  throw 'Falta migracion SIL 032 en la rama actual.'
}
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
  throw 'Falta el runner aislado en la rama actual.'
}

Write-Host 'SHA256 comprobado. Iniciando PostgreSQL temporal sin red...'
try {
  # La misma version que usa compose.yaml. No hay red ni puertos publicados.
  $id = & docker run --detach --pull=never --name $container --network none --env POSTGRES_USER=vitalia_restore --env POSTGRES_DB=vitalia_restored --env POSTGRES_HOST_AUTH_METHOD=trust --env PGUSER=vitalia_restore --env PGDATABASE=vitalia_restored --env PGHOST=/var/run/postgresql --env VITALIA_ISOLATED_REHEARSAL=YES postgres:16.15-bookworm
  Assert-Docker 'creacion del contenedor temporal'
  if (-not ($id | Out-String).Trim()) { throw 'Docker no devolvio ID.' }
  $created = $true

  $ready = $false
  for ($attempt = 0; $attempt -lt 45; $attempt++) {
    & docker exec $container pg_isready --username=$user --dbname=$db *> $null
    if ($LASTEXITCODE -eq 0) {
      $ready = $true
      break
    }
    Start-Sleep -Seconds 1
  }
  if (-not $ready) { throw 'PostgreSQL temporal no inicio.' }

  $targetBackup = '{0}:{1}' -f $container, $remoteBackup
  & docker cp $absoluteBackup $targetBackup
  Assert-Docker 'copia del respaldo al contenedor temporal'
  $remoteHashOutput = & docker exec $container sha256sum $remoteBackup
  Assert-Docker 'SHA256 dentro del contenedor temporal'
  $match = [regex]::Match(($remoteHashOutput | Out-String).Trim(), '^([0-9a-fA-F]{64})\s+')
  if (-not $match.Success -or $match.Groups[1].Value.ToUpperInvariant() -ne $localHash) {
    throw 'Respaldo copiado con SHA256 diferente.'
  }

  Write-Host 'Restaurando el respaldo en PostgreSQL aislado...'
  & docker exec $container pg_restore --username=$user --dbname=$db --no-owner --no-privileges --single-transaction --exit-on-error $remoteBackup
  Assert-Docker 'restauracion del dump en base temporal'

  & docker exec $container mkdir -p $workdir
  Assert-Docker 'creacion de directorio temporal'
  $targetDir = '{0}:{1}' -f $container, $workdir
  & docker cp $sqlDir $targetDir
  Assert-Docker 'copia de migraciones SQL al contenedor'
  $targetRunner = '{0}:{1}' -f $container, "$workdir/run.sh"
  & docker cp $runner $targetRunner
  Assert-Docker 'copia del runner'
  Write-Host 'Ensayando SQL 012-032 exclusivamente en la copia temporal...'
  & docker exec $container sh "$workdir/run.sh"
  Assert-Docker 'ejecucion y validacion del ensayo'
  $approved = $true
}
finally {
  if ($created -and $container -match '^vitalia-migration-rehearsal-[a-f0-9]{12}$') {
    # Solo nuestro contenedor temporal y su volumen anonimo.
    & docker rm --force --volumes $container *> $null
    if ($LASTEXITCODE -ne 0) {
      Write-Warning ('No se pudo retirar el contenedor temporal: ' + $container)
    }
  }
}

if ($approved) {
  Write-Host ''
  Write-Host 'MIGRACIONES SIL 012-032 ENSAYADAS CON EXITO' -ForegroundColor Green
  Write-Host 'Respaldo original: intacto.'
  Write-Host 'Bases existentes: sin cambios.'
  Write-Host 'Migraciones DEMO 033-037: pendientes de redisenar.'
}
