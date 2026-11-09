# Respaldo consistente y verificable de PostgreSQL principal Vitalia.
# No detiene contenedores, no altera tablas y no ejecuta migraciones.
# Requiere Docker Desktop y PowerShell en Windows.
# Uso desde la raiz del repositorio:
#   .\deploy\backup-main-before-sil.ps1
[CmdletBinding()]
param(
  [string]$BackupDirectory = (Join-Path $HOME "Vitalia-Backups")
)

$ErrorActionPreference = 'Stop'
$container = 'vitalia-postgres-1'
$databaseExpected = 'vitalia'
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$name = "vitalia-principal-pre-sil-$stamp.dump"
$inside = "/tmp/$name"
$outside = Join-Path $BackupDirectory $name
$createdInside = $false

function Assert-Docker([string]$Step) {
  if ($LASTEXITCODE -ne 0) {
    throw "Fallo en $Step. No se realizó ninguna migración."
  }
}

try {
  $state = docker inspect --format '{{.State.Running}}' $container 2>&1
  Assert-Docker 'la inspeccion de PostgreSQL'
  if (($state | Out-String).Trim() -ne 'true') {
    throw 'El PostgreSQL principal no está ejecutándose.'
  }

  # Verificar que el nombre de la base coincide: no respaldar otra por error.
  $verify = 'set -eu; test "$POSTGRES_DB" = "vitalia"; test -n "$POSTGRES_USER"; printf "%s" "$POSTGRES_DB"'
  $db = docker exec $container sh -c $verify 2>&1
  Assert-Docker 'la verificacion de la base'
  if (($db | Out-String).Trim() -ne $databaseExpected) {
    throw 'La base indicada por el contenedor no es vitalia.'
  }

  if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
  }
  if (Test-Path -LiteralPath $outside) {
    throw 'El archivo de respaldo ya existe. No se sobrescribirá.'
  }

  Write-Host 'Generando respaldo PostgreSQL consistente...'
  # El archivo se genera dentro del contenedor para evitar que PowerShell
  # convierta la salida binaria a texto en su redireccionamiento.
  $dump = 'set -eu; umask 077; test "$POSTGRES_DB" = "vitalia"; pg_dump --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --format=custom --no-owner --no-privileges --file="$1"; test -s "$1"; pg_restore --list "$1" >/dev/null'
  $createdInside = $true
  docker exec $container sh -c $dump sh $inside
  Assert-Docker 'pg_dump y la verificacion interna con pg_restore'

  $remoteHash = docker exec $container sh -c 'sha256sum "$1" | cut -d " " -f1' sh $inside
  Assert-Docker 'el calculo de la huella del respaldo en Docker'

  docker cp "${container}:${inside}" "$outside"
  Assert-Docker 'la copia del archivo binario fuera del contenedor'

  if (-not (Test-Path -LiteralPath $outside -PathType Leaf)) {
    throw 'No se encontró el archivo local después de docker cp.'
  }
  $backup = Get-Item -LiteralPath $outside
  if ($backup.Length -lt 1024) {
    throw 'El archivo de respaldo es anormalmente pequeño; revisa la ejecución.'
  }

  $hash = Get-FileHash -LiteralPath $outside -Algorithm SHA256
  if ($hash.Hash.ToLowerInvariant() -ne ($remoteHash | Out-String).Trim().ToLowerInvariant()) {
    throw 'La huella SHA256 local difiere del respaldo del contenedor. No utilizar este archivo.'
  }
  Write-Host ''
  Write-Host 'RESPALDO CREADO' -ForegroundColor Green
  Write-Host "Destino: $($backup.FullName)"
  Write-Host "Tamaño: $($backup.Length) bytes"
  Write-Host "SHA256: $($hash.Hash)"
  Write-Host 'Verificado: pg_restore --list dentro de PostgreSQL.'
  Write-Host 'IMPORTANTE: aún falta comprobar una restauración en un contenedor independiente.'
  Write-Host 'Conserva este archivo fuera de Git y protegido; puede contener datos privados.'
}
finally {
  if ($createdInside) {
    # Limpiar exclusivamente el archivo temporal creado por este script.
    $cleanup = 'case "$1" in /tmp/vitalia-principal-pre-sil-*.dump) rm -f -- "$1";; *) exit 1;; esac'
    & docker exec $container sh -c $cleanup sh $inside *> $null
  }
}
