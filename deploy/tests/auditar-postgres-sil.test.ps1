$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ps = Join-Path $root 'deploy/auditar-postgres-sil.ps1'
$sqlFile = Join-Path $root 'deploy/sql/auditar-privilegios-sil.sql'

# Parseo real de PowerShell sin ejecutar Docker ni consultar instancias.
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  $ps, [ref]$tokens, [ref]$errors
) | Out-Null
if ($errors.Count -gt 0) {
  throw 'El script de auditoria PowerShell contiene errores de sintaxis.'
}

$sql = [System.IO.File]::ReadAllText($sqlFile)
$body = [regex]::Replace($sql, '(?m)^\s*--[^\r\n]*', '')
$statements = @($body.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
if ($statements.Count -ne 5) {
  throw 'La auditoria SQL no contiene el numero esperado de sentencias.'
}
if ($statements[0] -cne 'BEGIN TRANSACTION READ ONLY' -or
    $statements[-1] -cne 'ROLLBACK') {
  throw 'La auditoria SQL debe abrir READ ONLY y terminar con ROLLBACK.'
}
foreach ($statement in $statements[1..3]) {
  if ($statement -notmatch '(?is)^SELECT\s+') {
    throw 'La auditoria SQL solo debe ejecutar sentencias SELECT.'
  }
}
if ($sql -match '(?im)^\s*(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|GRANT|REVOKE|TRUNCATE|COPY|DO|CALL)\b') {
  throw 'La auditoria SQL contiene una instruccion no permitida.'
}

$source = [System.IO.File]::ReadAllText($ps)
if ($source -notmatch 'config --quiet' -or
    $source -notmatch "docker compose exec -T postgres" -or
    $source -notmatch "ON_ERROR_STOP=1") {
  throw 'Falta uno de los resguardos de ejecucion de solo lectura.'
}
Write-Host 'Auditoria PostgreSQL: sintaxis y contrato de solo lectura aprobados.'
Write-Host 'Este test estatico NO consulta roles reales ni verifica Tailscale.'
