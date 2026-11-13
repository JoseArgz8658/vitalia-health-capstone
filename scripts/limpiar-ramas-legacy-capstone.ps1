# Limpieza conservadora de ramas remotas antiguas — Vitalia Health (Capstone 2026)
# Requisitos: PowerShell, Git, remoto 'origin' configurado y permisos de escritura.
# Sin -Apply SOLO muestra las ramas candidatas. No toca develop, main ni ramas con commits exclusivos.
# Ejemplo (desde la raíz del repositorio):
# powershell -ExecutionPolicy Bypass -File .\scripts\limpiar-ramas-legacy-capstone.ps1
# powershell -ExecutionPolicy Bypass -File .\scripts\limpiar-ramas-legacy-capstone.ps1 -Apply
[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$protected = @(
  'develop', 'main', 'Kusack01-patch-1',
  'docs/problemas-instalacion', 'fix/consolidacion-seguridad-sil'
)
$candidates = @(
  'feat/android-apk-sil-20261112',
  'feat/sil-integracion-vitalia-principal',
  'feat/sil-operador-ux-postanalitica',
  'feat/sil-paciente-experiencia-visual',
  'feat/sil-paciente-identidad-y-ayuda',
  'feat/sil-paciente-portal',
  'feat/sil-portal-activacion-demo',
  'feature/sil-ordenes-muestras-mvp',
  'feature/sil-paciente-solo-lectura',
  'feature/sil-simulador-analizador',
  'fix/sil-navegacion-operador'
)

git rev-parse --is-inside-work-tree | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Ejecuta el script dentro de un repositorio Git.' }
git remote get-url origin | Out-Null
if ($LASTEXITCODE -ne 0) { throw "No existe remoto 'origin'." }
git fetch origin --prune
if ($LASTEXITCODE -ne 0) { throw 'Falló git fetch; no se realizará limpieza.' }
git show-ref --verify --quiet 'refs/remotes/origin/develop'
if ($LASTEXITCODE -ne 0) { throw 'La rama remota origin/develop no existe.' }

Write-Host 'Vitalia: verificación conservadora de ramas heredadas' -ForegroundColor Cyan
$ready = @()
foreach ($name in $candidates) {
  if ($protected -contains $name) { Write-Host "PROTEGIDA: $name"; continue }
  $remoteRef = "refs/remotes/origin/$name"
  git show-ref --verify --quiet $remoteRef
  if ($LASTEXITCODE -ne 0) { Write-Host "AUSENTE: $name"; continue }
  git merge-base --is-ancestor "origin/$name" 'origin/develop'
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "CON CAMBIOS NO INCORPORADOS (no borrar): $name"
    continue
  }
  $ready += $name
  Write-Host "APTA (contenido ya en develop): $name" -ForegroundColor Green
}

Write-Host "Ramas aptas: $($ready.Count)."
if (-not $Apply) {
  Write-Host 'Simulación finalizada. No se borró ninguna rama.' -ForegroundColor Yellow
  Write-Host 'Para ejecutar debes invocar -Apply y confirmar manualmente.'
  return
}
if ($ready.Count -eq 0) { Write-Host 'No hay ramas aptas.'; return }
$confirmation = Read-Host "Para borrar estas $($ready.Count) ramas de origin, escribe BORRAR"
if ($confirmation -cne 'BORRAR') { Write-Host 'Cancelado sin cambios.'; return }
foreach ($name in $ready) {
  git push origin --delete $name
  if ($LASTEXITCODE -ne 0) { Write-Warning "Falló eliminación: $name"; continue }
  Write-Host "Eliminada del remoto: $name" -ForegroundColor Green
}
Write-Host 'Fin. Los PR y commits históricos de GitHub no se borraron.'
