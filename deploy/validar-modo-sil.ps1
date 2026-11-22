[CmdletBinding()]
param(
  [string]$ArchivoEntorno = (Join-Path (Split-Path $PSScriptRoot -Parent) '.env')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ArchivoEntorno -PathType Leaf)) {
  throw 'No existe .env en la raiz del proyecto. No se compilara la web SIL.'
}

# Se leen solo tres claves, sin imprimir el contenido de .env ni sus secretos.
$settings = @{}
foreach ($line in (Get-Content -LiteralPath $ArchivoEntorno)) {
  if ($line -match '^\s*(VITALIA_SIL_MAIN_MODE|VITALIA_SIL_DEMO|PGDATABASE)\s*=\s*(.*?)\s*$') {
    $key = $Matches[1]
    $value = $Matches[2].Trim()
    if ($settings.ContainsKey($key)) {
      throw ('Configuracion duplicada: ' + $key)
    }
    if ($value.Length -ge 2 -and (
        ($value.StartsWith("'") -and $value.EndsWith("'")) -or
        ($value.StartsWith('"') -and $value.EndsWith('"'))
      )) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $settings[$key] = $value
  }
}

if ($settings['VITALIA_SIL_MAIN_MODE'] -cne 'YES') {
  throw 'SIL principal desactivado: VITALIA_SIL_MAIN_MODE debe ser exactamente YES en .env.'
}
if ($settings['PGDATABASE'] -cne 'vitalia') {
  throw 'SIL principal requiere PGDATABASE=vitalia con el esquema 041 previamente aprobado.'
}
if ($settings['VITALIA_SIL_DEMO'] -ceq 'YES') {
  throw 'No se permite activar SIL principal junto con VITALIA_SIL_DEMO=YES.'
}

Write-Host 'Preflight de configuracion SIL aprobado (solo lectura).'
