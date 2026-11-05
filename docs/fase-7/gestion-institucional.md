# Gestión institucional — Continuación de fase 7.2

Preparé creación y consulta de clínicas/sucursales en CAM-088. La estructura 013 ya validada no se modifica; la auditoría nueva requiere 014. La API restringe estas acciones al administrador y no concede acceso médico. (José Aránguiz)

## Comprobar código

Desde la raíz del repositorio de pruebas, conserva cambios locales, actualiza fase-7/02-clinicas-pertenencias y ejecuta:

```powershell
cd backend
npm test
$LASTEXITCODE
cd ..\apps\vitalia
flutter analyze
flutter test
$LASTEXITCODE
```

El backend debe aprobar 530 pruebas en 46 suites. Flutter incluye cuatro pruebas nuevas sobre las 86 anteriores; su ejecución en Windows está pendiente. Las pruebas no aplican migraciones a vitalia_dev. (José Aránguiz)

## Preparar PostgreSQL después de las pruebas

Conserva un respaldo actualizado de vitalia_dev y confirma que 013 está aplicada. Revisa backend/database/migrations/014_institution_audit.sql. Con credenciales administrativas temporales, desde backend:

```powershell
node --env-file=.env dist/database/migrate-institution-audit.js
$LASTEXITCODE
```

Esperado: migración de auditoría institucional aplicada, salida 0. Si ya estaba aplicada con la misma huella, no repite la creación. Al aplicar se esperan 32 tablas y 14 migraciones. No edites las migraciones anteriores ni arranques Compose sobre volúmenes habituales sin revisión: migrate-all descubre la nueva 014 automáticamente. (José Aránguiz)

Revisa el archivo backend/database/permissions/institutions-app.sql completo y ejecútalo en Query Tool como postgres sobre vitalia_dev. Debe terminar en COMMIT. No conviertas vitalia_app en administrador ni le concedas acceso completo a las seis tablas de 013. La aplicación mantiene su usuario habitual. (José Aránguiz)

Después, como administrador temporal, comprueba:

```powershell
node --env-file=.env dist/database/verify-institutions.js
$LASTEXITCODE
```

Esperado: Gestión institucional: 14 comprobaciones correctas. Datos sintéticos revertidos, salida 0. Este verificador requiere el catálogo territorial y revierte sus registros; no crea una clínica de demostración permanente. Utiliza PostgreSQL, sin S3 ni Ollama. (José Aránguiz)

## Recorrido de aplicación

Reinicia API y Flutter. Entra como administrador y pulsa el icono de hospital con ayuda Clínicas y sucursales. Consulta el listado, agrega una clínica ficticia y vuelve a abrir la pantalla para comprobar persistencia. Abre Ver sucursales bajo esa clínica y agrega una sucursal con dirección y comuna; teléfono, piso y unidad son opcionales. Cancela otro formulario y comprueba que no se agrega. Comprueba que un paciente o profesional no tenga este acceso. (José Aránguiz)

La clínica y sucursal creadas desde la interfaz sí quedan guardadas: usa únicamente datos de prueba. No se ofrecen eliminación, cambios de estado, designación de jefe clínico ni consulta de exámenes en esta pantalla. Las invitaciones requerirán el procedimiento institucional acordado y sus pruebas de autorización. (José Aránguiz)
