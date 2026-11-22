[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# Diagnostico manual. No se debe ejecutar contra datos clinicos reales.
# No lee el contenido de .env ni imprime nombres de usuario o credenciales.
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$query = Join-Path $PSScriptRoot 'sql/auditar-privilegios-sil.sql'
if (-not (Test-Path -LiteralPath $query -PathType Leaf)) {
  throw 'No se encontro la consulta de auditoria.'
}

Push-Location $root
try {
  # --quiet evita imprimir la configuracion expandida, que contiene secretos.
  & docker compose config --quiet
  if ($LASTEXITCODE -ne 0) { throw 'Compose no tiene una configuracion valida.' }

  $running = @(& docker compose ps --status running --services)
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar el estado de Docker.' }
  if ($running -notcontains 'api' -or $running -notcontains 'postgres') {
    throw 'La API y PostgreSQL deben estar en ejecucion para auditar el rol utilizado.'
  }

  # Comprobar sin imprimir si ambas aplicaciones usan el mismo rol/base.
  $apiUser = & docker compose exec -T api node -p 'process.env.PGUSER'
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo comprobar el usuario de la API.' }
  $dbUser = & docker compose exec -T postgres sh -c 'printf "%s" "$POSTGRES_USER"'
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo comprobar el usuario de PostgreSQL.' }
  $apiDatabase = & docker compose exec -T api node -p 'process.env.PGDATABASE'
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo comprobar la base de la API.' }
  $dbDatabase = & docker compose exec -T postgres sh -c 'printf "%s" "$POSTGRES_DB"'
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo comprobar la base de PostgreSQL.' }
  if ([string]$apiUser -cne [string]$dbUser -or
      [string]$apiDatabase -cne [string]$dbDatabase) {
    throw 'Roles o bases distintos entre API y PostgreSQL: no atribuir resultados al usuario de la API.'
  }

  Write-Host 'Conexion de API y PostgreSQL: mismo rol/base (nombres ocultos).'
  Write-Host 'Ejecutando SELECT de metadatos mediante transaccion READ ONLY.'

  # El contenedor usa sus propias variables; ninguna clave se pasa en la linea
  # de comandos. -w evita solicitudes interactivas de contrasena.
  $sql = [System.IO.File]::ReadAllText($query)
  $command = 'exec psql -X -w -A -t -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
  $sql | & docker compose exec -T postgres sh -c $command
  if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo completar la auditoria de solo lectura.'
  }

  Write-Host 'Auditoria finalizada. Ningun privilegio fue modificado.'
  Write-Host 'No publicar salidas completas del entorno ni archivos .env.'
} finally {
  Pop-Location
}
