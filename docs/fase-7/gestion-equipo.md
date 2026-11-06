# Gestión del equipo — Continuación de fase 7.2

Actualicé el acceso y la activación en [modos-acceso.md](modos-acceso.md), correspondiente a CAM-091. Para la versión actual sigo primero esa guía: la activación está en una dirección independiente, el inicio permite Paciente/Profesional y la administración tiene su propia dirección. Conservo las dos entregas, manual y por correo pendiente de configuración. Las cifras de pruebas de los apartados siguientes corresponden al incremento original. (José Aránguiz)

Preparé el incremento de [CAM-090](../cambios-codigo/CAM-090-gestion-equipo-pertenencias.md). El flujo de autorización, invitaciones y activación de CAM-089 ya fue comprobado en Windows y PostgreSQL 16, incluida reutilización de código y revocación. La nueva gestión requiere sus propias comprobaciones y la migración 016. (José Aránguiz)

## 1. Comprobar el código en Windows

Desde la raíz del repositorio de pruebas, en PowerShell de VS Code, conserva cualquier cambio local antes de actualizar. La rama debe ser `fase-7/02-clinicas-pertenencias`. (José Aránguiz)

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

Añadí 33 pruebas backend a las 566 anteriores y ocho Flutter a las 96 anteriores. Se esperan 599 pruebas backend en 48 suites y 104 pruebas Flutter si todas se ejecutan. Los resultados de Windows todavía deben comprobarse. No cambié dependencias; las pruebas no aplican 016 a `vitalia_dev`. (José Aránguiz)

## 2. Respaldo y revisión

Con las pruebas aprobadas, genera en pgAdmin un respaldo actualizado de `vitalia_dev`, formato Custom, con estructura, datos, funciones y secuencias. Conserva los originales de S3: no están incluidos en el archivo de PostgreSQL. Comprueba que 015 está aplicada y revisa `backend/database/migrations/016_membership_management.sql`. Detén temporalmente la API antes de aplicar el esquema y permisos. (José Aránguiz)

No reutilices el respaldo anterior a 015 como si incluyera autorizaciones y cuentas activadas. No arranques Compose sobre volúmenes habituales antes de revisar y respaldar: `migrate-all` descubre 016. Esta guía corresponde al PostgreSQL local sin Docker. (José Aránguiz)

## 3. Aplicación y verificador administrativo

Desde `backend`, después del respaldo y revisión, usa credenciales administrativas temporales. La API conservará su usuario limitado `vitalia_app`; no cambies permanentemente su `.env`. (José Aránguiz)

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
    node --env-file=.env dist/database/migrate-membership-management.js
    if ($LASTEXITCODE -ne 0) { throw "La migración no terminó correctamente." }
    node --env-file=.env dist/database/verify-team.js
    if ($LASTEXITCODE -ne 0) { throw "El verificador no terminó correctamente." }
}
finally {
    $env:PGUSER = $usuarioAnterior
    $env:PGPASSWORD = $passwordAnterior
    $env:PGDATABASE = $baseAnterior
    $credencial = $null
}
```

Espero `Migración de gestión de pertenencias aplicada.` —o ya aplicada si coincide— y `Gestión del equipo: 37 comprobaciones correctas. Datos sintéticos revertidos.` El verificador necesita el catálogo territorial y permisos administrativos para preparar/revertir sus registros; no necesita S3 u Ollama. La migración permanece aplicada. Se esperan 39 tablas y 16 migraciones desde la base previa de 37 tablas. (José Aránguiz)

## 4. Permisos de aplicación

Revisa `backend/database/permissions/team-app.sql`. Abre Query Tool como administrador sobre `vitalia_dev` y ejecuta el archivo completo. Debe terminar con COMMIT sin errores. No concedas actualización global de cuentas, roles o pertenencias ni conviertas `vitalia_app` en propietario o superusuario. Conservo las concesiones revisadas de 015 y añado solamente las necesarias para este módulo. (José Aránguiz)

Reinicia la API con `npm start` y Flutter como en la guía de instalación. La activación de invitaciones con especialidades utiliza la nueva tabla después de este cambio, por lo que el esquema y sus permisos deben estar listos antes de probarla. (José Aránguiz)

## 5. Recorrido del jefe clínico

Usa la clínica ficticia y el profesional de prueba que activaste en CAM-089. Entra como jefe, abre **Equipo de mi clínica**, selecciona su institución y pulsa **Ver equipo de esta clínica**. Debes ver función, actividad, sucursales y especialidades institucionales. La pertenencia del jefe no debe mostrar edición; el profesional ordinario sí debe mostrar **Editar pertenencia**. (José Aránguiz)

Edita una pertenencia de prueba. Cambia una selección disponible, pulsa Cancelar y comprueba que se conserva lo anterior. Después edita, desactiva **Pertenencia activa**, intenta guardar sin motivo y comprueba la validación. Ingresa un motivo de prueba de al menos cinco caracteres y guarda. Actualiza o reabre la pantalla: debe permanecer suspendida. Abre **Ver historial** y comprueba autor, fecha, motivo y estados. Luego reactiva con un nuevo motivo; deben conservarse ambos cambios en el historial. (José Aránguiz)

No incluyas datos de pacientes en el motivo. Si no tienes sucursales o especialidades configuradas, las selecciones pueden estar vacías; puedes comprobar suspensión y reactivación sin inventar catálogos. Las especialidades recuperadas desde invitaciones siguen siendo selección institucional, no acreditación profesional. Las relaciones personales anteriores se conservan por separado. (José Aránguiz)

## 6. Consulta y límites

Como administrador, abre **Incorporación institucional**, selecciona una clínica y pulsa **Ver equipo de esta clínica**: podrás consultar listado e historial, sin botones para editar pertenencias. Un profesional ordinario seguirá sin jefatura activa para entrar a esta gestión. La API también exige la autorización aunque se manipule la interfaz. (José Aránguiz)

Para comprobar conflicto de formularios, abre la edición de la misma pertenencia de prueba en dos sesiones del jefe. Guarda un cambio desde la primera y después uno distinto desde la segunda. La segunda debe informar conflicto y conservar el cambio guardado primero. Cancela el formulario antiguo y actualiza antes de continuar. No cambies filas reales por SQL para simularlo. La concurrencia de carga y entre múltiples instancias requiere validación adicional. (José Aránguiz)

Si pruebas una nueva invitación con especialidad después de aplicar 016 y permisos, activa un correo nuevo controlado por el equipo y comprueba que su especialidad aparece en el listado institucional. No publiques códigos o contraseñas. El resto del flujo de invitaciones se conserva. (José Aránguiz)

Suspender una pertenencia no elimina la cuenta ni equivale a revocar las asignaciones de pacientes del flujo anterior. Las pertenencias de otras instituciones y revisiones históricas se conservan. La atención y autorización clínica por examen se implementarán en su bloque correspondiente. (José Aránguiz)
