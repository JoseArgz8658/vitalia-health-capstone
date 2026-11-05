# Modos de acceso y activación independiente

> Actualización: preparé la separación de contraseñas en CAM-092 y ajusté el acceso y cambio desde el perfil en CAM-093. Para el código actual, seguir [contraseñas por modo](contrasenas-por-modo.md); el flujo y las cifras siguientes describen CAM-091. (José Aránguiz)

Preparé [CAM-091](../cambios-codigo/CAM-091-modos-acceso-activacion-independiente.md) en la rama `fase-7/02-clinicas-pertenencias`. La gestión del equipo anterior quedó validada; este incremento requiere su propia migración y comprobaciones. No ejecutes 017 sin respaldo y revisión. (José Aránguiz)

## 1. Actualizar y comprobar código

Desde la raíz del repositorio de pruebas, en PowerShell de VS Code, comprueba la rama y conserva cambios locales antes de actualizar. (José Aránguiz)

```powershell
git status --short
git branch --show-current
git pull --ff-only
cd backend
npm test
$LASTEXITCODE
cd ..\apps\vitalia
flutter analyze
flutter test
$LASTEXITCODE
```

Espero 617 pruebas backend en 49 suites. Añadí siete pruebas Flutter a las 104 anteriores: se esperan 111 si todas se ejecutan. Los resultados en Windows siguen pendientes. No actualicé dependencias. Estas pruebas no migran tu base. (José Aránguiz)

## 2. Respaldo, migración y permisos

Genera un respaldo actualizado de `vitalia_dev` en pgAdmin, formato Custom, con estructura, datos, funciones y secuencias. Conserva los originales de S3. Revisa `017_account_modes.sql` y confirma que 016 está aplicada. Detén la API antes de aplicar el esquema y permisos: las sesiones nuevas requieren la columna del modo, y las cuentas nuevas requieren permisos para su concesión inicial. No arranques Compose sobre volúmenes habituales sin revisión porque `migrate-all` descubre 017. (José Aránguiz)

Después del respaldo, desde `backend`, usa credenciales administrativas temporales: (José Aránguiz)

```powershell
$usuarioAnterior = $env:PGUSER
$passwordAnterior = $env:PGPASSWORD
$baseAnterior = $env:PGDATABASE
try {
    $credencial = Get-Credential -UserName postgres -Message "Credenciales administrativas de PostgreSQL local"
    if ($null -eq $credencial) { throw "Operación cancelada." }
    $env:PGUSER = "postgres"
    $env:PGPASSWORD = $credencial.GetNetworkCredential().Password
    $env:PGDATABASE = "vitalia_dev"
    node --env-file=.env dist/database/migrate-account-modes.js
    if ($LASTEXITCODE -ne 0) { throw "La migración no terminó correctamente." }
    node --env-file=.env dist/database/verify-account-modes.js
    if ($LASTEXITCODE -ne 0) { throw "El verificador no terminó correctamente." }
}
finally {
    $env:PGUSER = $usuarioAnterior
    $env:PGPASSWORD = $passwordAnterior
    $env:PGDATABASE = $baseAnterior
    $credencial = $null
}
```

Espero `Migración de modos de cuenta aplicada.` —o ya aplicada si coincide— y `Modos de cuenta: 27 comprobaciones correctas. Datos sintéticos revertidos.` El verificador usa datos ficticios y no necesita S3/Ollama. La migración queda aplicada; no cambies manualmente roles de personas reales para simular los casos. (José Aránguiz)

En pgAdmin, Query Tool como administrador sobre `vitalia_dev`, revisa y ejecuta **todo** `backend/database/permissions/account-modes-app.sql`. Debe terminar en COMMIT sin errores. Conserva los permisos de 015/016; no conviertas `vitalia_app` en superusuario ni concedas actualización global de cuentas o sesiones. Después reinicia API y Flutter. (José Aránguiz)

## 3. Direcciones y modos

Con la web local en puerto 5173, utiliza estas direcciones. Si ejecutas en otro puerto o dominio, adapta la base conservando las rutas. (José Aránguiz)

| Dirección local | Uso |
|---|---|
| `http://localhost:5173/` | Inicio en Paciente, con botón para cambiar a Profesional. |
| `http://localhost:5173/#/administracion` | Acceso administrativo separado. |
| `http://localhost:5173/#/activar-invitacion` | Activación pública protegida por el código; no tiene botón en el inicio. |

Comprueba que Paciente rechaza una cuenta que solo tenga concesión profesional y Profesional rechaza una cuenta que solo tenga concesión de paciente. El mensaje de credenciales o modo incorrectos no otorga permisos ni revela si una cuenta existe. Un administrador debe entrar por su dirección separada. El jefe entra por Profesional y conserva el alcance de su institución. (José Aránguiz)

## 4. Entrega manual y correo

Desde quien invita, conserva el código mostrado una sola vez y comparte por privado con el destinatario su clínica, correo invitado, dirección de activación, código y vencimiento de 48 horas. No publiques el código en capturas o documentos. El listado no lo recupera; si se pierde, revoca la invitación y emite otra. (José Aránguiz)

Mantengo **las dos formas de entrega**. La manual está disponible; la pantalla indica que el envío por correo está pendiente de configurar. No pulses ni esperes un envío automático todavía. Cuando configure el servicio se enviarán dirección y código al correo invitado, manteniendo la opción manual. (José Aránguiz)

La dirección mostrada se obtiene del origen web actual. Para una compilación que necesite una base web explícita, puede definirse `VITALIA_WEB_URL` con `--dart-define`. La dirección debe ser pública o accesible desde el equipo del destinatario; `localhost` solo sirve en el mismo equipo. No se incorpora ningún código a la URL. No se implementaron enlaces universales móviles en este incremento. (José Aránguiz)

## 5. Cuenta nueva

Invita un correo de prueba sin cuenta. Abre la dirección independiente e ingresa código, nombres, contraseña propia y confirmación. Tras activar, vuelve al inicio y selecciona Profesional para entrar. La nueva cuenta tendrá permiso profesional; no recibirá automáticamente un perfil de paciente o permisos administrativos. (José Aránguiz)

## 6. Cuenta de paciente existente y dos modos

Utiliza un paciente de prueba que ya tenga una cuenta y datos personales. Desde el jefe clínico invita ese mismo correo. Abre la dirección independiente en otra pestaña y activa **Ya tengo una cuenta en Vitalia**. Ingresa el código, nombre/apellido, el correo invitado y su contraseña actual. Deja desactivado el ingreso con perfil profesional existente si esa cuenta todavía es solo paciente. Marca la aceptación y pulsa **Iniciar sesión y aceptar invitación**. (José Aránguiz)

Vuelve al inicio: con el mismo correo y contraseña, Paciente debe conservar su espacio y datos propios; Profesional debe abrir el espacio profesional. Una sesión de paciente anterior debe continuar siendo de paciente. Aceptar la invitación no asigna pacientes ni permite consultar exámenes ajenos. Los nombres de un perfil ya registrado no deben sustituirse por lo escrito en la aceptación. (José Aránguiz)

Comprueba con otra cuenta de prueba que el mismo código no permite aceptar para un correo distinto. No compartas aquí contraseñas o códigos. La reutilización, vencimiento y revocación conservan sus reglas. (José Aránguiz)

## 7. Profesional existente en otra clínica

Invita un correo profesional de prueba a otra clínica. En la dirección independiente selecciona **Ya tengo una cuenta**, activa el ingreso con el perfil profesional existente y utiliza su contraseña actual. Tras aceptar, conserva la pertenencia anterior y añade la nueva. Una pertenencia duplicada en la misma clínica requiere gestión del jefe, no otra activación. Las facultades de jefe no se trasladan a otra institución automáticamente. (José Aránguiz)

Una concesión global profesional revocada no se reactiva con este flujo. La suspensión de una pertenencia sigue siendo distinta de los permisos globales y de las asignaciones anteriores. La acreditación profesional y atención por examen mantienen sus pendientes. (José Aránguiz)