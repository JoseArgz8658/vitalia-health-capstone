# Ensayo SOLO de SQL 041 sobre un respaldo POST-040 (36 migraciones).
# No escribe en vitalia-postgres-1, no reinicia contenedores existentes.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$BackupFile,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSha256
)
$ErrorActionPreference='Stop'
$container='vitalia-pending-041-'+[guid]::NewGuid().ToString('N').Substring(0,12)
$localDump=(Resolve-Path -LiteralPath $BackupFile -ErrorAction Stop).Path
$localSql=Join-Path $PSScriptRoot '..\backend\database\migrations\041_sil_main_pending_referrals.sql'
$remoteDump='/tmp/vitalia-post-040.dump'
$remoteSql='/tmp/041_sil_main_pending_referrals.sql'
$created=$false
$passed=$false
function Check([string]$step) {
  if($LASTEXITCODE -ne 0){throw "Fallo en $step; la base principal no se modifico."}
}
if(-not (Test-Path -LiteralPath $localSql -PathType Leaf)){
  throw 'No se encontro SQL 041 en el repositorio.'
}
$hash=(Get-FileHash -LiteralPath $localDump -Algorithm SHA256).Hash
if($hash -ne $ExpectedSha256.ToUpperInvariant()){
  throw 'Respaldo con SHA256 incorrecto: ensayo cancelado.'
}
if((Get-Item -LiteralPath $localDump).Length -lt 1024){
  throw 'El archivo de respaldo es demasiado pequeno.'
}
try{
  $id=& docker run --detach --pull=never --name $container --network none --env POSTGRES_USER=vitalia_restore --env POSTGRES_DB=vitalia_restored --env POSTGRES_HOST_AUTH_METHOD=trust postgres:16.15-bookworm
  Check 'creacion del contenedor temporal'
  if(-not ($id | Out-String).Trim()){throw 'Docker no devolvio el ID del contenedor.'}
  $created=$true
  $ready=$false
  for($i=0;$i -lt 45;$i++){
    & docker exec $container pg_isready --username=vitalia_restore --dbname=vitalia_restored *> $null
    if($LASTEXITCODE -eq 0){$ready=$true;break}
    Start-Sleep -Seconds 1
  }
  if(-not $ready){throw 'PostgreSQL aislado no inicio.'}

  & docker cp $localDump ('{0}:{1}' -f $container,$remoteDump)
  Check 'copia del respaldo'
  $remoteHash=(& docker exec $container sha256sum $remoteDump | Out-String).Trim()
  Check 'SHA256 del respaldo copiado'
  if($remoteHash -notmatch '^([0-9a-fA-F]{64})\s+' -or $Matches[1].ToUpperInvariant() -ne $hash){
    throw 'Los bytes dentro del contenedor no coinciden.'
  }

  Write-Host 'Restaurando la base POST-040 en contenedor aislado...'
  & docker exec $container pg_restore --username=vitalia_restore --dbname=vitalia_restored --no-owner --no-privileges --single-transaction --exit-on-error $remoteDump
  Check 'restauracion completa del dump'

  $sql="SELECT current_database()='vitalia_restored' AND (SELECT count(*)=36 FROM public.vitalia_schema_migrations) AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='040_sil_main_clinical_access') AND NOT EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='041_sil_main_pending_referrals') AND to_regclass('public.vitalia_sil_main_pending_requests') IS NULL;"
  $beforeOk=(& docker exec $container psql -X -A -t -v ON_ERROR_STOP=1 -U vitalia_restore -d vitalia_restored -c $sql | Out-String).Trim()
  Check 'historial de 36 migraciones'
  if($beforeOk -ne 't'){throw 'El respaldo no contiene las 36 migraciones esperadas.'}

  $counts="SELECT (SELECT count(*) FROM public.vitalia_accounts)::text || '|' || (SELECT count(*) FROM public.vitalia_sessions)::text || '|' || (SELECT count(*) FROM public.vitalia_documents)::text || '|' || (SELECT count(*) FROM public.vitalia_sil_main_orders)::text || '|' || (SELECT count(*) FROM public.vitalia_sil_main_medical_requests)::text;"
  $before=(& docker exec $container psql -X -A -t -v ON_ERROR_STOP=1 -U vitalia_restore -d vitalia_restored -c $counts | Out-String).Trim()
  Check 'filas historicas previas'

  & docker cp $localSql ('{0}:{1}' -f $container,$remoteSql)
  Check 'copia del archivo de migracion'
  Write-Host 'Aplicando SQL 041 solo en PostgreSQL temporal...'
  & docker exec $container psql -X -v ON_ERROR_STOP=1 --single-transaction -U vitalia_restore -d vitalia_restored -f $remoteSql | Out-Null
  Check 'SQL 041 en base temporal'
  $afterSql="SELECT to_regclass('public.vitalia_sil_main_pending_requests') IS NOT NULL AND (SELECT count(*)=36 FROM public.vitalia_schema_migrations) AND (SELECT count(*)=0 FROM public.vitalia_sil_main_pending_requests);"
  $afterOk=(& docker exec $container psql -X -A -t -v ON_ERROR_STOP=1 -U vitalia_restore -d vitalia_restored -c $afterSql | Out-String).Trim()
  Check 'esquema posterior'
  $after=(& docker exec $container psql -X -A -t -v ON_ERROR_STOP=1 -U vitalia_restore -d vitalia_restored -c $counts | Out-String).Trim()
  Check 'filas historicas posteriores'
  if($afterOk -ne 't' -or $before -ne $after){
    throw 'Migracion o integridad historica no verificada.'
  }
  $passed=$true
}finally{
  if($created -and $container -match '^vitalia-pending-041-[a-f0-9]{12}$'){
    & docker rm --force --volumes $container *> $null
    if($LASTEXITCODE -ne 0){Write-Warning ('Retirar contenedor temporal manualmente: '+$container)}
  }
}
if($passed){
  Write-Host 'ENSAYO AISLADO DE MIGRACION 041 APROBADO' -ForegroundColor Green
  Write-Host 'Respaldo POST-040 verificado y datos historicos preservados.'
  Write-Host 'No se modifico la base principal ni el respaldo.'
}
