param(
    [ValidateSet('Start', 'Stop', 'Credentials', 'Reset', 'Remove')]
    [string]$Action = 'Start',
    [switch]$ConfirmRemoval,
    [string]$FlutterCommand = 'flutter'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    function Invoke-ShowcaseCompose {
        & docker compose --env-file .env.usability -p vitalia-usability -f compose.showcase.yaml @args
        if ($LASTEXITCODE -ne 0) { throw 'Falló Docker Compose para vitalia-usability.' }
    }
    function New-ShowcaseSecret {
        $bytes = New-Object byte[] 32
        $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
        return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    }

    if ($Action -in @('Reset', 'Remove')) {
        if (!$ConfirmRemoval) { throw 'Confirma el retiro exclusivo de showcase con -ConfirmRemoval.' }
        if (!(Test-Path .env.usability)) { throw 'No se encontró la configuración de showcase.' }
        Invoke-ShowcaseCompose down --volumes
        Remove-Item -LiteralPath .env.usability
        if ($Action -eq 'Remove') { return }
    }
    if ($Action -eq 'Stop') {
        Invoke-ShowcaseCompose stop
        return
    }
    if ($Action -eq 'Start' -or $Action -eq 'Reset') {
        if (!(Test-Path .env.usability)) {
            $pg = New-ShowcaseSecret
            @(
                "POSTGRES_PASSWORD=$pg"
                "PGPASSWORD=$pg"
                "SHOWCASE_ADMIN_PASSWORD=$(New-ShowcaseSecret)"
                "SHOWCASE_OPERATOR_PASSWORD=$(New-ShowcaseSecret)"
                "SHOWCASE_PATIENT_PASSWORD=$(New-ShowcaseSecret)"
            ) | Set-Content -LiteralPath .env.usability -Encoding ascii
        }
        Push-Location apps/vitalia
        try {
            & $FlutterCommand build web --release --no-web-resources-cdn --output build/usability `
                --dart-define=VITALIA_SIL_MAIN_MODE=true `
                --dart-define=VITALIA_API_SAME_ORIGIN=true `
                --dart-define=VITALIA_SHOWCASE=true
            if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación web del showcase.' }
        } finally { Pop-Location }
        Invoke-ShowcaseCompose up -d --build --wait
        Write-Host 'Showcase listo en http://127.0.0.1:5174'
        return
    }
    if ($Action -eq 'Credentials') {
        $credentials = Get-Content -LiteralPath .env.usability -Raw | ConvertFrom-StringData
        Write-Host "Administrador admin@showcase.example.invalid / $($credentials.SHOWCASE_ADMIN_PASSWORD)"
        Write-Host "Operador revisor martin.sepulveda.sur@altocanelo.example.invalid / $($credentials.SHOWCASE_OPERATOR_PASSWORD)"
        Write-Host "Paciente fran25valenzuela@correo.example.invalid / $($credentials.SHOWCASE_PATIENT_PASSWORD)"
    }
} finally {
    Pop-Location
}
