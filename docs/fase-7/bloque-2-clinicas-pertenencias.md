# Fase 7.2 — Clínicas y pertenencias

Preparé la base institucional en fase-7/02-clinicas-pertenencias. Este primer incremento contiene estructura y verificaciones; no habilita gestión clínica ni invitaciones. La evidencia y límites están en [CAM-087](../cambios-codigo/CAM-087-estructura-clinicas-pertenencias.md). (José Aránguiz)

| Tabla nueva | Finalidad |
|---|---|
| vitalia_clinics | Nombre, contacto opcional y estado de la clínica. |
| vitalia_branches | Clínica, comuna, nombre, dirección, piso/unidad opcionales y estado. |
| vitalia_specialties | Catálogo de especialidades sin cargar una lista clínica no revisada. |
| vitalia_professional_specialties | Relación entre perfil profesional y especialidad. |
| vitalia_clinic_memberships | Pertenencia del profesional a una clínica; inactiva por defecto. |
| vitalia_branch_memberships | Vinculación con sucursales de la misma clínica mediante FK compuestas. |

Aplicar 013 añade seis tablas a las 25 de la fase 7.1: el esquema pasará a 31. Una fila profesional no acredita habilitación; una pertenencia no concede acceso clínico automático. No se asignan clínicas a documentos antiguos ni se cambian revisiones. (José Aránguiz)

## Comprobar código antes de modificar PostgreSQL

Desde la raíz en PowerShell de VS Code, conserva los cambios locales antes de cambiar de rama:

```powershell
git status --short
git fetch origin
git switch fase-7/02-clinicas-pertenencias
cd backend
npm test
$LASTEXITCODE
```

Esperado: 504 pruebas de 45 suites, salida 0. Estas pruebas no migran tu base. No necesitas repetir Flutter por este bloque exclusivamente de backend/datos. (José Aránguiz)

## Aplicación deliberada después de respaldo y revisión

Comprueba en backend/.env y en Query Tool que la base es vitalia_dev y que 012 ya está aplicada. Genera y conserva un respaldo actualizado de la fase 7.1. No reutilices un respaldo anterior de 17 tablas como si incluyera perfiles y ubicación. Revisa el SQL 013 completo antes de ejecutarlo. (José Aránguiz)

Con credenciales administrativas temporales en la terminal, desde backend:

```powershell
node --env-file=.env dist/database/migrate-clinics-memberships.js
$LASTEXITCODE
node --env-file=.env dist/database/verify-clinics-memberships.js
$LASTEXITCODE
```

El primer comando debe informar Migración de clínicas y pertenencias aplicada y salida 0. Si ya estaba aplicada y coincide, lo informa sin duplicar objetos. Ejecuta el verificador solo si la migración terminó correctamente. Esperado: Clínicas y pertenencias: 28 comprobaciones correctas. Datos sintéticos revertidos, salida 0. Usa una conexión administrativa para preparar y revertir esos datos; el usuario de la API continúa siendo vitalia_app. (José Aránguiz)

No conviertas vitalia_app en propietario, superusuario o cuenta de migraciones. No cambies permanentemente backend/.env a postgres. No se requiere otorgar permisos sobre las seis tablas nuevas para el flujo actual. El CRUD institucional todavía no está habilitado. (José Aránguiz)

## Docker y reversión

No inicies Compose sobre volúmenes habituales sin revisar y respaldar: migrate-all descubrirá 013. La construcción de la etapa test, por sí sola, no aplica el cambio a una base externa. La ejecución del contenedor y sus roles requieren validación aparte. (José Aránguiz)

Si falla la migración, la transacción intenta revertirla. Si falla el verificador, revierte sus datos sintéticos y conserva el esquema aplicado. No borres tablas ni edites migraciones ya aplicadas para forzar una repetición. La restauración o eliminación de una copia de pruebas debe planificarse identificando su base y respaldo. (José Aránguiz)

## Continuación funcional

Faltan servicios y pantallas de gestión institucional con auditoría y restricciones por institución. Antes de activar jefes clínicos se incorporará el flujo de autorización externa verificable e invitación; el administrador no podrá nombrarlos por decisión propia. Después se integrarán gestión de profesionales y atención por examen. Ninguna de esas capacidades se considera disponible por esta migración. (José Aránguiz)

## Continuación de gestión — CAM-088

Registré el inventario confirmado de 31 tablas y 13 migraciones. Preparé API y pantalla administrativa para crear/consultar clínicas y sucursales. La auditoría nueva utiliza 014, con permisos específicos y aplicación pendiente. La guía está en [gestion-institucional.md](gestion-institucional.md). Los permisos de esta continuación son distintos de la estructura inicial sin concesiones. No habilité pertenencias, invitaciones, edición ni desactivación por API. (José Aránguiz)

## Autorización e invitaciones — CAM-089

Preparé la continuación institucional con 015, cinco tablas nuevas, servicio y pantallas. La creación y consulta de instituciones de CAM-088 ya se comprobaron en Windows y PostgreSQL 16; esta nueva continuación todavía requiere sus propias pruebas y aplicación. La guía está en [invitaciones-institucionales.md](invitaciones-institucionales.md) y la evidencia en [CAM-089](../cambios-codigo/CAM-089-autorizacion-invitaciones-institucionales.md). No cambian 013 ni 014. (José Aránguiz)

## Gestión del equipo — CAM-090

Preparé listado y gestión auditada de pertenencias de profesionales ordinarios. El jefe actúa solo en su clínica; el administrador consulta sin editar. La migración 016 conserva las relaciones personales previas y añade especialidades por pertenencia y auditoría. La guía es [gestion-equipo.md](gestion-equipo.md). Su aplicación en PostgreSQL 16 y las comprobaciones Windows están pendientes; los resultados y límites se registran en CAM-090. (José Aránguiz)

## Modos de acceso y aceptación de cuentas existentes — CAM-091

Preparé el siguiente incremento con 017, sesiones ligadas al modo y activación independiente del inicio. Una cuenta existente acepta la invitación tras autenticarse, conservando contraseña y datos. Mantengo entrega manual y envío por correo pendiente de configuración. La guía está en [modos-acceso.md](modos-acceso.md); las comprobaciones en Windows/PostgreSQL 16 siguen pendientes. (José Aránguiz)
