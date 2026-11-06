# Invitaciones institucionales — Continuación de fase 7.2

Actualicé el acceso y la activación en [modos-acceso.md](modos-acceso.md), correspondiente a CAM-091. Para la versión actual sigo primero esa guía: la activación está en una dirección independiente, el inicio permite Paciente/Profesional y la administración tiene su propia dirección. Conservo las dos entregas, manual y por correo pendiente de configuración. Las cifras de pruebas de los apartados siguientes corresponden al incremento original. (José Aránguiz)

Implementé el flujo descrito en [CAM-089](../cambios-codigo/CAM-089-autorizacion-invitaciones-institucionales.md). Esta guía valida primero código y después PostgreSQL. No doy por aplicada 015 por haber aprobado las pruebas automatizadas. (José Aránguiz)

## 1. Actualizar y comprobar código en Windows

Desde la raíz del repositorio de pruebas, en PowerShell de VS Code, comprueba la rama y conserva cualquier cambio local antes de actualizar. No descartes archivos para forzar el pull. (José Aránguiz)

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

La rama es `fase-7/02-clinicas-pertenencias`. Espero 566 pruebas backend en 47 suites y salida 0. Añadí seis pruebas Flutter a las 90 anteriores; su resultado debe comprobarse en Windows. Si alguna comprobación falla, conserva la salida y resuélvela antes de aplicar la migración. No actualicé dependencias. (José Aránguiz)

## 2. Respaldar y revisar la base antes de migrar

Genera un respaldo actualizado de `vitalia_dev` en pgAdmin, incluyendo estructura, datos y secuencias. Conserva los archivos S3 compartidos; este respaldo no contiene sus originales. Confirma que 014 está aplicada y revisa `backend/database/migrations/015_institution_invitations.sql`. La migración añade cinco tablas; no elimina ni transforma registros anteriores. (José Aránguiz)

No inicies Compose sobre volúmenes habituales antes de esta revisión y respaldo: `migrate-all` descubre 015 automáticamente. Las comprobaciones siguientes corresponden a PostgreSQL local, sin Docker. No cambies permanentemente `backend/.env` a `postgres`; la API continúa usando `vitalia_app`. (José Aránguiz)

## 3. Aplicar y verificar con credenciales administrativas temporales

Después del respaldo y de las pruebas aprobadas, desde `backend`, detén temporalmente la API para aplicar los permisos de forma deliberada. Ejecuta este bloque en una terminal PowerShell; solicita tu contraseña local de PostgreSQL sin imprimirla. (José Aránguiz)

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
    node --env-file=.env dist/database/migrate-invitations.js
    if ($LASTEXITCODE -ne 0) { throw "La migración no terminó correctamente." }
    node --env-file=.env dist/database/verify-invitations.js
    if ($LASTEXITCODE -ne 0) { throw "El verificador no terminó correctamente." }
}
finally {
    $env:PGUSER = $usuarioAnterior
    $env:PGPASSWORD = $passwordAnterior
    $env:PGDATABASE = $baseAnterior
    $credencial = $null
}
```

Espero `Migración de invitaciones institucionales aplicada.` —o ya aplicada si coincide su huella— e `Invitaciones institucionales: 41 comprobaciones correctas. Datos sintéticos revertidos.` El verificador usa una transacción y datos ficticios; no conserva cuentas clínicas ni necesita S3/Ollama. Las migraciones sí permanecen aplicadas. (José Aránguiz)

## 4. Conceder permisos de aplicación

Revisa `backend/database/permissions/invitations-app.sql`. En pgAdmin, abre Query Tool conectado como administrador a **vitalia_dev** y ejecuta el archivo completo. Debe terminar con `COMMIT` sin errores. No conviertas `vitalia_app` en superusuario o propietario ni le concedas acceso completo a todas las tablas. (José Aránguiz)

Vuelve a iniciar la API con `npm start` y Flutter como en la guía de instalación. El bloque anterior restaura las variables de entorno de la terminal. Las sesiones, documentos y asignaciones anteriores conservan su contrato. (José Aránguiz)

## 5. Recorrido de prueba del administrador

Usa una clínica ficticia activa que ya hayas creado. En el espacio administrativo abre **Incorporación institucional**, selecciona la clínica y pulsa **Registrar autorización**. Ingresa el correo nuevo del jefe designado, nombre/cargo/contacto del solicitante, referencia ficticia identificada como prueba y fecha en formato `AAAA-MM-DD`. No uses una autorización ficticia para presentar una institución real como verificada. (José Aránguiz)

Abre **Autorizaciones institucionales**. El registro debe estar pendiente. Confirma la comprobación externa únicamente cuando corresponda y pulsa **Registrar mi verificación**. En las pruebas utiliza datos sintéticos claramente identificados. Comprueba que quedan identificados el verificador y la fecha. (José Aránguiz)

Pulsa **Invitar primer jefe clínico**, ingresa exactamente el correo designado y selecciona su autorización verificada. Opcionalmente elige sucursales propias y especialidades existentes. Si necesitas una especialidad para la demostración, el administrador puede usar **Agregar especialidad**, con una denominación revisada por el equipo; no se carga un catálogo médico automático. Guarda y entrega el código por privado solo al destinatario. No publiques códigos en capturas ni en documentación. Si sales de la pantalla o pierdes el código, revoca la invitación antes de crear otra. (José Aránguiz)

## 6. Activar y probar el alcance del jefe

Cierra la sesión administrativa. En el inicio de sesión pulsa **Activar invitación profesional**, pega el código y completa primer nombre, primer apellido, contraseña propia y confirmación. Tras activar, inicia sesión con el correo invitado. La aplicación no revela ni establece una contraseña compartida. (José Aránguiz)

Abre **Equipo de mi clínica**. Solo debe aparecer la institución de la jefatura activa. Invita otro correo nuevo como profesional, seleccionando opcionalmente sucursales y especialidades. Activa esa invitación desde el inicio de sesión. El profesional ordinario no debe poder invitar compañeros ni consultar la gestión de otras clínicas. Tener perfil profesional pendiente no acredita habilitación para ofrecer atención real. (José Aránguiz)

Comprueba además: contraseña y confirmación distintas no envían la activación; reutilizar el código no activa otra cuenta; revocar una invitación impide usarla; un correo diferente al designado no sirve para invitar jefe; una cuenta existente no cambia de rol o contraseña. La expiración, revocación de autorización y pérdida de jefatura del emisor también están cubiertas por el verificador sintético. No cambies fechas ni pertenencias reales para simularlas. (José Aránguiz)

Las cuentas creadas desde la interfaz permanecen: usa correos de prueba controlados. La nueva pertenencia no asigna pacientes; sin asignaciones previas, un profesional nuevo debe seguir sin exámenes visibles. Revocar una invitación no suspende una cuenta activada. La suspensión auditada y la incorporación de correos ya registrados se mantienen pendientes. (José Aránguiz)
