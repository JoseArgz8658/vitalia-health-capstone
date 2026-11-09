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
$staging = Join-Path ([System.IO.Path]::GetTempPath()) $container
$staged = $false
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Copy-LinuxText([string]$Source, [string]$Destination, [bool]$AllowBom = $false) {
  $text = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($Source))
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    if (-not $AllowBom) { throw ('SQL con BOM UTF-8: ' + [System.IO.Path]::GetFileName($Source)) }
    $text = $text.Substring(1)
  }
  $text = $text.Replace("`r`n", "`n")
  if ($text.Contains("`r") -or $text.Contains([string][char]0)) {
    throw ('Texto incompatible: ' + [System.IO.Path]::GetFileName($Source))
  }
  [System.IO.File]::WriteAllText($Destination, $text, $strictUtf8)
}

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

try {
  $null = New-Item -ItemType Directory -Path $staging
  $staged = $true
  $stagedMigrations = Join-Path $staging 'migrations'
  $null = New-Item -ItemType Directory -Path $stagedMigrations
  $stagedRunner = Join-Path $staging 'run.sh'
  Copy-LinuxText $runner $stagedRunner $true
  foreach ($number in 1..32) {
    $prefix = '{0:D3}' -f $number
    $matchesForNumber = @(Get-ChildItem -LiteralPath $sqlDir -File -Filter ("${prefix}_*.sql"))
    if ($matchesForNumber.Count -ne 1) {
      throw "Se esperaba exactamente un SQL para $prefix."
    }
    $migration = $matchesForNumber[0]
    Copy-LinuxText $migration.FullName (Join-Path $stagedMigrations $migration.Name)
  }
  Write-Host 'SHA256 comprobado. Iniciando PostgreSQL temporal sin red...'
  # La misma version que usa compose.yaml. No hay red ni puertos publicados.
  $id = & docker run --detach --pull=never --name $container --network none --env POSTGRES_USER=vitalia_restore --env POSTGRES_DB=vitalia_restored --env POSTGRES_HOST_AUTH_METHOD=trust --env PGUSER=vitalia_restore --env PGDATABASE=vitalia_restored --env PGHOST=/var/run/postgresql --env VITALIA_ISOLATED_REHEARSAL=YES postgres:16.15-bookworm
  Assert-Docker 'creacion del contenedor temporal'
  if (-not ($id | Out-String).Trim()) { throw 'Docker no devolvio ID.' }
  $created = $true

  $ready = $false
  for ($attempt = 0; $attempt -lt 45; $attempt++) {
    # El entrypoint inicia un servidor intermedio antes de hacer exec de postgres.
    $process = & docker exec $container cat /proc/1/comm 2>$null
    if ($LASTEXITCODE -ne 0 -or $process -ne 'postgres') {
      Start-Sleep -Seconds 1
      continue
    }
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
  & docker cp $stagedMigrations $targetDir
  Assert-Docker 'copia de migraciones SQL al contenedor'
  $targetRunner = '{0}:{1}' -f $container, "$workdir/run.sh"
  & docker cp $stagedRunner $targetRunner
  Assert-Docker 'copia del runner'
  & docker exec $container sh -n "$workdir/run.sh"
  Assert-Docker 'sintaxis del runner Linux'
  Write-Host 'Ensayando SQL 012-032 exclusivamente en la copia temporal...'
  & docker exec $container sh "$workdir/run.sh"
  Assert-Docker 'ejecucion y validacion del ensayo'
  $approved = $true
}
finally {
  if ($staged) {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Continue
  }
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
