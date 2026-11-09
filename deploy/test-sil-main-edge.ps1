[CmdletBinding()]
param([switch]$Manual)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$backend = Join-Path $root 'backend'
$app = Join-Path $root 'apps\vitalia'
$container = 'vitalia-edge-qa-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$temp = Join-Path ([System.IO.Path]::GetTempPath()) $container
$created = $false

function Assert-Native([string]$Step) {
  if ($LASTEXITCODE -ne 0) { throw ('Falló: ' + $Step) }
}

$testEnv = @{
  PGHOST = '127.0.0.1'
  PGPORT = '55439'
  PGDATABASE = 'vitalia_restored'
  PGUSER = 'vitalia_restore'
  PGPASSWORD = [guid]::NewGuid().ToString('N')
  VITALIA_ISOLATED_REHEARSAL = 'YES'
  VITALIA_JOURNEY_DB_CONTAINER = $container
  VITALIA_JOURNEY_WEB = Join-Path $temp 'web'
  VITALIA_JOURNEY_PLAYWRIGHT = Join-Path $temp 'node_modules\playwright'
  VITALIA_JOURNEY_MANUAL = $(if ($Manual) { 'YES' } else { 'NO' })
  VITALIA_JOURNEY_FIXTURE = Join-Path $temp 'informe-operador.pdf'
}
$previousEnv = @{}
foreach ($key in $testEnv.Keys) {
  $previousEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
try {
  & docker image inspect --format '{{.Id}}' postgres:16.15-bookworm vitalia-backend:local
  Assert-Native 'comprobar las imágenes locales del ensayo'

  $null = New-Item -ItemType Directory -Path $temp
  & npm --prefix $backend run build
  Assert-Native 'compilar el backend'
  Push-Location $app
  try {
    & flutter pub get
    Assert-Native 'resolver las dependencias de Flutter'
    & flutter build web --target=lib/main.dart --output $testEnv.VITALIA_JOURNEY_WEB --no-web-resources-cdn --dart-define=VITALIA_SIL_MAIN_MODE=true --dart-define=VITALIA_API_URL=http://127.0.0.1:3119
    Assert-Native 'compilar la web de prueba'
  } finally {
    Pop-Location
  }

  if (-not $Manual) {
    & npm install --prefix $temp --no-save playwright@1.58.2
    Assert-Native 'preparar Playwright para el Edge instalado'
  }
  foreach ($key in $testEnv.Keys) {
    [Environment]::SetEnvironmentVariable($key, $testEnv[$key], 'Process')
  }

  # La API local usa un puerto de prueba. La migración se ejecuta por loopback dentro del contenedor.
  $dockerArgs = @(
    'run', '--detach', '--rm', '--pull=never', '--name', $container,
    '--publish', '127.0.0.1:55439:5432', '--env', 'POSTGRES_USER=vitalia_restore',
    '--env', 'POSTGRES_DB=vitalia_restored', '--env', ('POSTGRES_PASSWORD=' + $testEnv.PGPASSWORD),
    'postgres:16.15-bookworm'
  )
  & docker @dockerArgs
  Assert-Native 'crear PostgreSQL temporal'
  $created = $true

  $ready = $false
  for ($attempt = 0; $attempt -lt 45; $attempt++) {
    & docker exec $container pg_isready -h 127.0.0.1 -U vitalia_restore -d vitalia_restored *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 1
  }
  if (-not $ready) { throw 'PostgreSQL temporal no inició.' }

  & node (Join-Path $backend 'test\sil-main-journey.cjs')
  Assert-Native 'ensayar el flujo del operador'
} finally {
  if ($created) {
    & docker stop $container *> $null
    if ($LASTEXITCODE -ne 0) {
      Write-Warning ('Revisa el contenedor temporal ' + $container)
    }
  }
  foreach ($key in $previousEnv.Keys) {
    [Environment]::SetEnvironmentVariable($key, $previousEnv[$key], 'Process')
  }
  if (Test-Path -LiteralPath $temp) {
    Remove-Item -LiteralPath $temp -Recurse -Force
  }
}
