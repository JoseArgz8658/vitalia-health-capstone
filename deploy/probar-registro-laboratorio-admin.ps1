# Comprueba acceso administrativo y registra LaboMed solo si no existe.
# Interactivo: contrasena oculta; no imprime contrasenas ni tokens.
# No altera roles, usuarios ni migraciones.
[CmdletBinding()]
param(
  [string]$Email = 'administrador.vitalia@gmail.com',
  [string]$LaboratoryName = 'LaboMed'
)
$ErrorActionPreference = 'Stop'
$api = 'http://127.0.0.1:3000'
$headers = $null
$credential = $null
$pointer = [IntPtr]::Zero

function StatusCode($errorRecord) {
  $response = $errorRecord.Exception.Response
  if ($null -eq $response) { return 'sin respuesta HTTP' }
  return [int]$response.StatusCode
}

try {
  Write-Host 'Diagnostico: autenticacion de administrador de Vitalia principal.'
  $credential = Read-Host 'Contrasena del administrador (oculta)' -AsSecureString
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential)
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  $payload = @{email=$Email.Trim().ToLowerInvariant();password=$plain;mode='administrador'} | ConvertTo-Json -Compress
  Remove-Variable plain -ErrorAction SilentlyContinue
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
  $pointer = [IntPtr]::Zero

  try {
    $session = Invoke-RestMethod -Uri "$api/api/auth/login" -Method Post -ContentType 'application/json' -Body $payload -TimeoutSec 30
  } catch {
    Write-Host ('LOGIN HTTP: ' + (StatusCode $_))
    throw 'Inicio de sesion fallido; no se registro laboratorio.'
  } finally {
    Remove-Variable payload -ErrorAction SilentlyContinue
  }
  if ($session.token -notmatch '^[a-f0-9]{64}$') {
    throw 'La API no devolvio token valido.'
  }
  $headers = @{Authorization='Bearer ' + $session.token}
  try {
    $me = Invoke-RestMethod -Uri "$api/api/auth/me" -Method Get -Headers $headers -TimeoutSec 30
  } catch {
    Write-Host ('ME HTTP: ' + (StatusCode $_))
    throw 'La API no reconoce la sesion; no se registro laboratorio.'
  }
  $role = [string]$me.user.role
  Write-Host ('ROL DESDE API /auth/me: ' + $role)
  if ($role -ne 'administrador' -or [string]$me.user.id -ne [string]$session.user.id) {
    throw 'Rol o identidad no coincidente; no se registro laboratorio.'
  }

  try {
    $existing = Invoke-RestMethod -Uri "$api/api/sil/main/labs" -Method Get -Headers $headers -TimeoutSec 30
  } catch {
    Write-Host ('LISTAR LABORATORIOS HTTP: ' + (StatusCode $_))
    throw 'La API rechaza el listado con esta cuenta; no se registro laboratorio.'
  }
  if ($null -eq $existing.laboratories) {
    throw 'La respuesta de la API no contiene laboratories.'
  }
  $labs = @($existing.laboratories)
  Write-Host ('LABORATORIOS VISIBLES: ' + $labs.Count)
  $matches = @($labs | Where-Object {
    $_.displayName -is [string] -and $_.displayName.Trim().Equals($LaboratoryName.Trim(), [StringComparison]::OrdinalIgnoreCase)
  })
  if ($matches.Count -gt 0) {
    Write-Host 'LABORATORIO YA EXISTE. No se crea un duplicado.'
    return
  }

  Write-Host ('Registrando laboratorio ' + $LaboratoryName + '...')
  try {
    $created = Invoke-RestMethod -Uri "$api/api/sil/main/labs" -Method Post -Headers $headers -ContentType 'application/json' -Body (@{displayName=$LaboratoryName} | ConvertTo-Json -Compress) -TimeoutSec 30
  } catch {
    Write-Host ('REGISTRAR LABORATORIO HTTP: ' + (StatusCode $_))
    throw 'El registro fue rechazado; revisar la version desplegada de la API.'
  }
  if ($created.laboratory.id -notmatch '^[a-f0-9-]{36}$') {
    throw 'La API no confirmo el identificador del laboratorio.'
  }
  Write-Host 'LABORATORIO REGISTRADO CORRECTAMENTE' -ForegroundColor Green
  Write-Host ('Nombre: ' + $created.laboratory.displayName)
} finally {
  if ($null -ne $headers) {
    try {
      Invoke-RestMethod -Uri "$api/api/auth/logout" -Method Post -Headers $headers -TimeoutSec 10 | Out-Null
    } catch {
      Write-Warning 'No se pudo confirmar el cierre de la sesion de diagnostico.'
    }
  }
  if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  if ($null -ne $credential) { $credential.Dispose() }
  Remove-Variable session,headers,me,credential -ErrorAction SilentlyContinue
}
