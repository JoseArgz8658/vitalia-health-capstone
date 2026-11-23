param([string]$FlutterCommand = 'flutter')

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
$flutter = Get-Command $FlutterCommand -CommandType Application -ErrorAction SilentlyContinue
if (!$flutter) {
    throw 'Flutter no está disponible. Usa -FlutterCommand con la ruta completa de flutter.bat.'
}

# Una web en modo SIL requiere una API en modo SIL y el esquema principal 041.
# Esta verificacion NO migra, no cambia .env y no inicia contenedores.
& (Join-Path $PSScriptRoot 'validar-modo-sil.ps1') -ArchivoEntorno (Join-Path $raiz '.env')

Push-Location (Join-Path $raiz 'apps/vitalia')
try {
  & $flutter.Source pub get
  if ($LASTEXITCODE -ne 0) { throw 'No se pudieron instalar las dependencias Flutter.' }

  # Un unico origen para web/API: funciona en localhost y Tailscale Serve,
  # sin incluir la direccion localhost del servidor en el navegador remoto.
  & $flutter.Source build web --release --no-web-resources-cdn `
    --dart-define=VITALIA_SIL_MAIN_MODE=true `
    --dart-define=VITALIA_API_SAME_ORIGIN=true
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar la web del SIL principal.' }
} finally {
  Pop-Location
}
Write-Host 'Web SIL compilada; NO se modificaron contenedores ni bases de datos.'
Write-Host 'Para actualizar solo Nginx, con API principal ya preparada:'
Write-Host 'docker compose --profile web up -d --force-recreate --no-deps web'
