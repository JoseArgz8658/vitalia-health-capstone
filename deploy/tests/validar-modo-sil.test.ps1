$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$validator = Join-Path (Split-Path $PSScriptRoot -Parent) 'validar-modo-sil.ps1'
$completed = 0

function Assert-Env([string]$Name, [string]$Content, [bool]$ShouldPass) {
  $path = Join-Path ([IO.Path]::GetTempPath()) ('vitalia-sil-test-' + [guid]::NewGuid().ToString('N') + '.env')
  try {
    [IO.File]::WriteAllText($path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    $passed = $true
    try {
      & $validator -ArchivoEntorno $path | Out-Null
    } catch {
      $passed = $false
    }
    if ($passed -ne $ShouldPass) {
      throw ('Resultado inesperado en escenario: ' + $Name)
    }
    $script:completed++
  } finally {
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  }
}

# Regresión: invocación sin -ArchivoEntorno desde -File de PowerShell.
# Usa directorio temporal y un .env sintético, sin leer secretos reales.
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('vitalia-sil-default-' + [guid]::NewGuid().ToString('N'))
$temporaryDeploy = Join-Path $temporaryRoot 'deploy'
try {
  [void](New-Item -ItemType Directory -Path $temporaryDeploy -Force)
  $temporaryScript = Join-Path $temporaryDeploy 'validar-modo-sil.ps1'
  Copy-Item -LiteralPath $validator -Destination $temporaryScript
  [IO.File]::WriteAllText((Join-Path $temporaryRoot '.env'),
    "PGDATABASE=vitalia`nVITALIA_SIL_MAIN_MODE=YES`n",
    (New-Object System.Text.UTF8Encoding($false)))
  $engine = (Get-Process -Id $PID).Path
  $message = & $engine -NoProfile -File $temporaryScript 2>&1
  if ($LASTEXITCODE -ne 0 -or
      (($message | Out-String) -notmatch 'Preflight de configuracion SIL aprobado')) {
    throw 'Invocacion sin argumentos del preflight debe usar el .env adyacente a deploy.'
  }
  $completed++
} finally {
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$base = "PGDATABASE='vitalia'`n"
Assert-Env 'configuracion correcta sin comillas' ($base + "VITALIA_SIL_MAIN_MODE=YES`n") $true
Assert-Env 'configuracion correcta entre comillas' ($base + "VITALIA_SIL_MAIN_MODE='YES'`n") $true
Assert-Env 'modo principal ausente' $base $false
Assert-Env 'modo principal desactivado' ($base + "VITALIA_SIL_MAIN_MODE=NO`n") $false
Assert-Env 'valor de modo en minusculas' ($base + "VITALIA_SIL_MAIN_MODE=yes`n") $false
Assert-Env 'base DEMO no autorizada' "PGDATABASE=vitalia_dev`nVITALIA_SIL_MAIN_MODE=YES`n" $false
Assert-Env 'base ausente' "VITALIA_SIL_MAIN_MODE=YES`n" $false
Assert-Env 'bandera duplicada' ($base + "VITALIA_SIL_MAIN_MODE=YES`nVITALIA_SIL_MAIN_MODE=NO`n") $false
Assert-Env 'DEMO simultanea' ($base + "VITALIA_SIL_MAIN_MODE=YES`nVITALIA_SIL_DEMO=YES`n") $false

$missing = Join-Path ([IO.Path]::GetTempPath()) ('vitalia-sil-missing-' + [guid]::NewGuid().ToString('N') + '.env')
try {
  & $validator -ArchivoEntorno $missing | Out-Null
  throw 'La ausencia de .env debio bloquear la operacion.'
} catch {
  if ($_.Exception.Message -eq 'La ausencia de .env debio bloquear la operacion.') {
    throw
  }
  $completed++
}

Write-Host ("Preflight SIL: $completed escenarios verificados.")
