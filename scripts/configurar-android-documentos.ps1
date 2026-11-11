$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$androidPath = Join-Path $repoRoot "apps/vitalia/android"
if (-not (Test-Path $androidPath)) {
    & (Join-Path $PSScriptRoot "preparar-android.ps1")
}
$activityPath = Join-Path $androidPath "app/src/main/kotlin/cl/vitalia/vitalia_health/MainActivity.kt"
$manifestPath = Join-Path $androidPath "app/src/debug/AndroidManifest.xml"
$networkPath = Join-Path $androidPath "app/src/debug/res/xml/vitalia_network_security_config.xml"
$templateRoot = Join-Path $PSScriptRoot "android"
if (-not (Test-Path $activityPath)) { throw "No se encontro la actividad Kotlin generada. No se modifica." }
if (-not (Test-Path $manifestPath)) { throw "No se encontro el manifiesto debug. No se modifica." }
$activityTemplate = [System.IO.File]::ReadAllText((Join-Path $templateRoot "MainActivity.kt"))
$manifestTemplate = [System.IO.File]::ReadAllText((Join-Path $templateRoot "AndroidManifest-debug.xml"))
$networkTemplate = [System.IO.File]::ReadAllText((Join-Path $templateRoot "vitalia_network_security_config.xml"))
$activityText = [System.IO.File]::ReadAllText($activityPath)
$generatedActivity = '(?s)^\s*package\s+cl\.vitalia\.vitalia_health\s*;?\s*import\s+io\.flutter\.embedding\.android\.FlutterActivity\s*;?\s*class\s+MainActivity\s*:\s*FlutterActivity\(\)\s*(\{\s*\})?\s*$'
if (-not [regex]::IsMatch($activityText, $generatedActivity) -and
    $activityText.Trim() -ne $activityTemplate.Trim()) {
    throw "MainActivity contiene cambios ajenos a la plantilla. Se detuvo sin reemplazar archivos."
}
[xml]$manifest = [System.IO.File]::ReadAllText($manifestPath)
$androidNs = "http://schemas.android.com/apk/res/android"
foreach ($node in $manifest.DocumentElement.ChildNodes) {
    if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
    # El adaptador XML puede ocultar Name con el atributo android:name.
    $elementName = $node.get_Name()
    if ($elementName -eq "uses-permission" -and
        $node.GetAttribute("name", $androidNs) -eq "android.permission.INTERNET" -and
        $node.Attributes.Count -eq 1) { continue }
    if ($elementName -eq "application" -and $node.ChildNodes.Count -eq 0 -and
        $node.Attributes.Count -eq 1 -and
        $node.GetAttribute("networkSecurityConfig", $androidNs) -eq "@xml/vitalia_network_security_config") { continue }
    throw "El manifiesto debug contiene configuracion no reconocida. No se reemplaza."
}
if (Test-Path $networkPath) {
    if ([System.IO.File]::ReadAllText($networkPath).Trim() -ne $networkTemplate.Trim()) {
        throw "La configuracion de red tiene cambios locales. No se reemplaza."
    }
}
if (-not $env:LOCALAPPDATA) { throw "No se encontro LOCALAPPDATA para guardar respaldos." }
$backupPath = Join-Path $env:LOCALAPPDATA ("VitaliaHealth/android-backups/" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
Copy-Item $activityPath (Join-Path $backupPath "MainActivity.kt")
Copy-Item $manifestPath (Join-Path $backupPath "AndroidManifest-debug.xml")
if (Test-Path $networkPath) { Copy-Item $networkPath (Join-Path $backupPath "vitalia_network_security_config.xml") }
New-Item -ItemType Directory -Path (Split-Path -Parent $networkPath) -Force | Out-Null
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($activityPath, $activityTemplate, $encoding)
[System.IO.File]::WriteAllText($manifestPath, $manifestTemplate, $encoding)
[System.IO.File]::WriteAllText($networkPath, $networkTemplate, $encoding)
Write-Host "Android preparado: descarga con selector y HTTP local debug para 10.0.2.2."
Write-Host "Respaldo de los archivos Android: $backupPath"
