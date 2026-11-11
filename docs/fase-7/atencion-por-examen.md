# Atención por examen — primer incremento

Preparé la estructura en `fase-7/03-atencion-examen`, dentro del repositorio de prueba. El alcance está en [CAM-094](../cambios-codigo/CAM-094-estructura-atencion-por-examen.md). Todavía no habilité selección de profesional ni derivaciones en la aplicación. (José Aránguiz)

## 1. Actualizar y comprobar

Desde la raíz, revisar que no haya cambios locales que deban conservarse:

```powershell
git status --short
git fetch origin
git switch fase-7/03-atencion-examen
git pull --ff-only
cd backend
npm test
$LASTEXITCODE
```

Esperado: 651 pruebas en 52 suites y salida 0. No hay cambios Flutter en este incremento.

## 2. Preparar aplicación local

Detener la API y guardar un respaldo nuevo de `vitalia_dev`, por ejemplo `vitalia_dev_antes_019`. El respaldo anterior a 018 no contiene el estado actual. Confirmar que 018 está aplicada. Revisar `backend/database/migrations/019_exam_care_reviews.sql` antes de aplicarla.

No ejecutar `npm run migrate` ni iniciar Compose antes del respaldo: el ejecutor general descubre automáticamente 019.

Desde `backend`, utilizar las credenciales administrativas solo durante el bloque:

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

    node --env-file=.env dist/database/migrate-exam-care.js
    if ($LASTEXITCODE -ne 0) { throw "Falló la migración 019." }
    node --env-file=.env dist/database/verify-exam-care.js
    if ($LASTEXITCODE -ne 0) { throw "Falló la verificación de atención." }
}
finally {
    $env:PGUSER = $usuarioAnterior
    $env:PGPASSWORD = $passwordAnterior
    $env:PGDATABASE = $baseAnterior
    $credencial = $null
}
```

Esperado:

```text
Migración de atención por examen aplicada.
Atención por examen: 54 comprobaciones correctas. Datos sintéticos revertidos.
```

Si no aparecen estos mensajes, no dar la verificación por completada únicamente por un código 0 de otro comando. No compartir contraseñas ni el contenido de `.env`.

## 3. Inventario y permisos

Después de aplicar, comprobar en pgAdmin sobre `vitalia_dev`:

```sql
SELECT current_database() AS base,
       (SELECT count(*) FROM pg_tables WHERE schemaname='public') AS tablas,
       (SELECT count(*) FROM public.vitalia_schema_migrations) AS migraciones,
       EXISTS(SELECT 1 FROM public.vitalia_schema_migrations
              WHERE version='019_exam_care_reviews') AS migracion_019_aplicada;
```

Esperado sin tablas ajenas al proyecto: 44 tablas, 19 migraciones y true. No hay script nuevo de permisos para vitalia_app: las tablas no se utilizan aún desde la API. No convertir vitalia_app en owner o superusuario.

Los perfiles verificados del verificador son exclusivamente datos ficticios y se revierten. No marcar médicos reales como verificados para obtener un catálogo lleno; falta implementar la verificación de sus credenciales con procedencia y auditoría.

## 4. Continuación dentro del bloque autorizado

Después de comprobar la estructura local, prepararé la verificación profesional necesaria para la elegibilidad, el catálogo de clínica/especialidad/profesional y la elección asociada al documento. Antes de habilitar lectura clínica, adaptaré el acceso a un solo examen y la auditoría, conservando un camino explícito para los documentos antiguos.

La derivación deberá cambiar el responsable mediante otra atención de la misma clínica, conservando la anterior. La segunda opinión conservará ambas revisiones. El chat y las explicaciones deberán seleccionar una revisión concreta sin mezclar autores ni versiones.

La extracción preliminar con advertencias, el envío de invitaciones por correo y la mejora visual del formulario de contraseña permanecen pendientes independientes. No considero finalizada la fase 7 por aplicar 019.

(José Aránguiz)
