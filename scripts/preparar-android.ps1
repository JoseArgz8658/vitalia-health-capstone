$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$androidPath = Join-Path $repoRoot "apps/vitalia/android"
if (Test-Path $androidPath) { throw "Android ya existe. No se modifica." }
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw "Flutter no esta en PATH." }
$templatePath = Join-Path ([System.IO.Path]::GetTempPath()) ("vitalia-" + [guid]::NewGuid())
try {
  & flutter create --no-pub --platforms=android --org cl.vitalia --project-name vitalia_health $templatePath
  if ($LASTEXITCODE -ne 0) { throw "No se pudo generar Android." }
  Copy-Item (Join-Path $templatePath "android") $androidPath -Recurse
} finally {
  if (Test-Path $templatePath) { Remove-Item $templatePath -Recurse -Force }
}
