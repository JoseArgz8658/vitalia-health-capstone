param(
    [ValidateSet('Start', 'Stop', 'Credentials', 'Reset', 'Remove')]
    [string]$Action = 'Start',
    [switch]$ConfirmRemoval
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    function Invoke-ShowcaseCompose {
        & docker compose --env-file .env.showcase -p vitalia-showcase -f compose.showcase.yaml @args
        if ($LASTEXITCODE -ne 0) { throw 'Falló Docker Compose para vitalia-showcase.' }
    }
    function New-ShowcaseSecret {
        $bytes = New-Object byte[] 32
        $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
        return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    }

    if ($Action -in @('Reset', 'Remove')) {
        if (!$ConfirmRemoval) { throw 'Confirma el retiro exclusivo de showcase con -ConfirmRemoval.' }
        if (!(Test-Path .env.showcase)) { throw 'No se encontró la configuración de showcase.' }
        Invoke-ShowcaseCompose down --volumes
        Remove-Item -LiteralPath .env.showcase
        if ($Action -eq 'Remove') { return }
    }
    if ($Action -eq 'Stop') {
        Invoke-ShowcaseCompose stop
        return
    }
    if ($Action -eq 'Start' -or $Action -eq 'Reset') {
        if (!(Test-Path .env.showcase)) {
            $pg = New-ShowcaseSecret
            @(
                "POSTGRES_PASSWORD=$pg"
                "PGPASSWORD=$pg"
                "SHOWCASE_ADMIN_PASSWORD=$(New-ShowcaseSecret)"
                "SHOWCASE_OPERATOR_PASSWORD=$(New-ShowcaseSecret)"
                "SHOWCASE_PATIENT_PASSWORD=$(New-ShowcaseSecret)"
            ) | Set-Content -LiteralPath .env.showcase -Encoding ascii
        }
        Push-Location apps/vitalia
        try {
            & flutter build web --release --no-web-resources-cdn --output build/showcase `
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
        $credentials = Get-Content -LiteralPath .env.showcase -Raw | ConvertFrom-StringData
        Write-Host "Administrador admin@showcase.example.invalid / $($credentials.SHOWCASE_ADMIN_PASSWORD)"
        Write-Host "Operadores operador-001, operador-002 y operador-003 @showcase.example.invalid / $($credentials.SHOWCASE_OPERATOR_PASSWORD)"
        Write-Host "Paciente paciente-001@showcase.example.invalid / $($credentials.SHOWCASE_PATIENT_PASSWORD)"
    }
} finally {
    Pop-Location
}
