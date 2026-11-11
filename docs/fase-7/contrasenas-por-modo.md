# Contraseñas por modo — comprobación local

Preparé este incremento en el repositorio de prueba y la rama `fase-7/02-clinicas-pertenencias`. Conservé los datos y la contraseña del modo original. Los accesos profesionales añadidos a pacientes requieren una contraseña diferente. (José Aránguiz)

## 1. Código y pruebas

Desde `backend`:

```powershell
npm test
$LASTEXITCODE
```

Desde `apps/vitalia`:

```powershell
flutter analyze
flutter test
$LASTEXITCODE
```

El backend comprobado tiene 646 pruebas en 51 suites; Flutter debería ejecutar 117. No confundir formato Dart con análisis o ejecución Flutter.

## 2. Respaldo y migración 018 — instalación inicial

Después de aprobar las pruebas, detener la API y guardar un respaldo de `vitalia_dev`. No aplicar 018 a otra base. No editar 017 ni migraciones anteriores.

Desde `backend`, usar credenciales administrativas temporales, conservando el usuario normal en `.env`:

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
    node --env-file=.env dist/database/migrate-mode-passwords.js
    if ($LASTEXITCODE -ne 0) { throw "Falló la migración 018." }
    node --env-file=.env dist/database/verify-mode-passwords.js
    if ($LASTEXITCODE -ne 0) { throw "Falló la verificación." }
}
finally {
    $env:PGUSER = $usuarioAnterior
    $env:PGPASSWORD = $passwordAnterior
    $env:PGDATABASE = $baseAnterior
    $credencial = $null
}
```

Resultados previstos con el código actual: migración de contraseñas por modo aplicada y 49 comprobaciones correctas con datos sintéticos revertidos. El verificador de modos anterior también utiliza ahora el contrato de 018.

En pgAdmin, conectado como postgres a `vitalia_dev`, ejecutar completo `backend/database/permissions/mode-passwords-app.sql`. Conservar los permisos anteriores. Esperar COMMIT. Reiniciar API y Flutter con la cuenta habitual `vitalia_app`.

La migración no añade tablas: se mantienen 40 tablas y pasan a 18 migraciones. Cierra las sesiones de modos adicionales para obligar a configurar su propia contraseña.

## 3. Cuenta que ya era paciente y profesional

Si ya apliqué 018 y sus permisos, no debo volver a aplicar ninguna migración para CAM-093. Actualizar el código y reiniciar la API y Flutter. El respaldo y las 39 comprobaciones de la instalación anterior se mantienen como evidencia de CAM-092; el verificador actual incorpora 49.

En el inicio de sesión ya no hay un botón de configuración. Seleccionar **modo profesional** e ingresar con la contraseña de paciente solo si aún no existe una contraseña profesional propia. La aplicación abre una configuración obligatoria antes de habilitar las funciones profesionales. Esta autorización dura cinco minutos y admite como máximo cinco intentos; al vencer o reiniciar la API, repetir el login.

Ingresar contraseña actual de paciente, nueva contraseña profesional diferente, confirmación y marcar la casilla. Guardar y volver a iniciar sesión como profesional con la nueva contraseña.

Comprobar:

- La cuenta sin permiso profesional se rechaza y no abre configuración.
- El acceso provisional no muestra pacientes, exámenes ni funciones de gestión.
- Sin confirmar la casilla no se envía el cambio.
- Una contraseña actual incorrecta o una nueva igual a la del paciente se rechaza.
- Después de guardar, paciente usa su contraseña anterior y profesional usa únicamente la nueva.
- Los datos y las pertenencias anteriores se conservan.

## 3.1. Cambio desde el perfil profesional

Con sesión profesional completa, abrir **Mi perfil → Seguridad de acceso → Cambiar contraseña profesional**. Ingresar contraseña profesional actual, nueva contraseña diferente, confirmarla y marcar la casilla. Guardar.

Comprobar que las sesiones profesionales anteriores quedan cerradas y que el nuevo acceso acepta únicamente la contraseña nueva. La sesión y la contraseña de paciente se conservan. Probar también una cuenta creada originalmente como profesional.

## 4. Primera invitación para un paciente

Crear una invitación para el correo de un paciente de prueba. Abrir `/#/activar-invitacion`, marcar **Ya tengo una cuenta en Vitalia** y mantener desactivado el ingreso con perfil profesional existente. Completar código, nombres, correo, contraseña actual y nueva contraseña profesional con confirmación. Aceptar.

Una contraseña actual incorrecta, la contraseña profesional igual a la de paciente o una confirmación diferente deben impedir la aceptación. Con datos correctos, comprobar ambos modos con sus respectivas contraseñas y conservar los exámenes y datos personales anteriores. La invitación se utiliza una sola vez.

## 5. Profesional que se incorpora a otra clínica

Marcar **Ya tengo una cuenta en Vitalia** y **Ingresar con mi perfil profesional existente**. Ingresar la contraseña profesional actual. No aparecen campos de nueva contraseña. Aceptar la invitación de otra clínica y comprobar que conserva su contraseña profesional y sus pertenencias anteriores.

Comprobar también el acceso del administrador y un profesional cuya cuenta original era profesional: sus contraseñas anteriores se mantienen.

La entrega manual de invitaciones continúa disponible. El envío por correo y la recuperación de contraseña siguen pendientes de implementación.

(José Aránguiz)
