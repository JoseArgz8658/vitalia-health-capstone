$ErrorActionPreference='Stop'
$raiz=Split-Path $PSScriptRoot -Parent
Push-Location (Join-Path $raiz 'apps/vitalia')
try{
 & flutter pub get
 if($LASTEXITCODE -ne 0){throw 'No se pudieron instalar las dependencias Flutter.'}
 & flutter build web --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
 if($LASTEXITCODE -ne 0){throw 'No se pudo compilar la web.'}
}finally{Pop-Location}
Write-Host 'Web compilada. Desde la raíz: docker compose --profile web up -d web'
