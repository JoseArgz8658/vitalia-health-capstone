# Operacion segura del SIL principal — Vitalia Health

Esta guia corresponde a la rama integrada `develop`. El SIL principal gestiona
solicitudes, ordenes, revision y publicacion de informes ya autorizados, con datos
**sinteticos**. No usar esta guia para operar con datos clinicos reales.

## 1. Condiciones antes de compilar o desplegar

El backend usa la base principal `vitalia`, esquema postanalitico **047**. La instalación 041 se actualiza mediante el procedimiento controlado. El código distingue:

| Elemento | Configuracion esperada |
| --- | --- |
| Backend (archivo `.env` en la raiz) | `PGDATABASE='vitalia'` y `VITALIA_SIL_MAIN_MODE='YES'` |
| Flutter web principal | `VITALIA_SIL_MAIN_MODE=true` |
| API web a traves de Nginx | `VITALIA_API_SAME_ORIGIN=true` |
| Docker Compose | API en `127.0.0.1:3000`; web en `127.0.0.1:5173` |
| Tailscale | Serve privado, sin publicar la base ni habilitar Funnel en el entorno principal |

La variable `VITALIA_SIL_MAIN_MODE` del backend es distinta de la definida
en Flutter: en el backend debe ser el texto **`YES`** (mayusculas), mientras
que la compilacion Flutter requiere **`true`**. La web compilada siempre
contiene estos valores hasta que se vuelva a compilar.

**Importante:** `deploy/configurar.ps1` prepara variables generales pero
**no** instala ni autoriza el SIL principal. En la base principal, el comando
`migrate-all` solo verifica el esquema; **no aplica** las migraciones 041 a 047.
Si el esquema no esta preparado, detener el proceso. El procedimiento de
migracion controlada exige respaldo, ensayo aislado y aprobacion explicita.
No modificar una base existente para satisfacer esta guia.

## 2. Preflight de solo lectura (PC anfitrion)

Desde PowerShell, en la carpeta que contiene `compose.yaml`:

```powershell
git status --short
git branch --show-current
docker compose ps

# Valida solo presencia y coherencia de variables; no muestra secretos.
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\validar-modo-sil.ps1
docker compose config --quiet
```

El verificador comprueba que `.env` tenga `VITALIA_SIL_MAIN_MODE=YES`,
`PGDATABASE=vitalia` y que no este habilitada la DEMO al mismo tiempo.
No reescribe `.env`, no consulta la base y no inicia contenedores.

Para confirmar el esquema si la API ya esta disponible en Docker:

```powershell
docker compose exec api node dist/database/migrate-all.js
```

En `vitalia` ese comando ejecuta una **consulta de solo lectura**: requiere
las migraciones SIL hasta la 047 y la tabla de derivaciones pendientes con cierre administrativo.
No ejecutar el migrador general contra `vitalia_dev` para estas comprobaciones,
porque ese entorno tiene una politica de migraciones diferente.

Si falla el preflight, revisar la configuracion con el responsable. **No**
modificar `.env`, ejecutar `migrate-main-sil --apply`, reconstruir la API ni
recrear PostgreSQL automaticamente para evitar el error. No compartir `.env`
ni la salida completa de configuraciones que puedan contener credenciales.

## 3. Compilar la web (sin desplegar)

Solo si el backend principal **ya esta preparado**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\crear-web.ps1
```

El script llama al preflight y ejecuta `flutter pub get` y:

```powershell
flutter build web --release --no-web-resources-cdn `
  --dart-define=VITALIA_SIL_MAIN_MODE=true `
  --dart-define=VITALIA_API_SAME_ORIGIN=true
```

El producto queda en `apps/vitalia/build/web`. La compilacion **no** publica
archivos en GitHub, no reinicia servicios ni cambia la base. La API del
navegador se conecta al mismo origen HTTPS o localhost que sirva Nginx.

## 4. Actualizar solamente la web (operacion autorizada)

Hacerlo cuando el equipo autorice la actualizacion y se haya comprobado la
version de codigo, respaldos necesarios y disponibilidad de la instancia.
En particular, no ejecutar estos pasos automaticamente desde GitHub:

```powershell
docker compose --profile web up -d --force-recreate --no-deps web
docker compose exec web nginx -t
Invoke-RestMethod http://127.0.0.1:5173/api/health

# Debe devolver 401 (ruta principal disponible, autenticacion requerida).
curl.exe -s -o NUL -w '%{http_code}' http://127.0.0.1:5173/api/sil/main/labs
```

El codigo HTTP `404` en `/api/sil/main/labs` indica que la ruta principal
no esta publicada. `401` confirma que existe y exige sesion, **no** demuestra
por si solo el recorrido completo ni que las migraciones esten correctas.
Ante resultados inesperados, no modificar las cuentas ni credenciales para
forzar el ingreso: revisar modo backend, Nginx y logs sin exponer secretos.

## 5. Git y pruebas

Los cambios se desarrollan en rama y pull request hacia `develop`; nunca
fusionar sin revisar CI. El workflow `SIL principal - pruebas de integracion`
incluye Jest, Flutter, recorrido Edge/PostgreSQL aislado y comprobaciones de
configuracion PowerShell. El workflow puede ejecutarse manualmente o por
cambios de codigo/deploy en PR y `develop`.

```powershell
# Comprobacion local de los escenarios de preflight, sin Docker ni .env real:
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\tests\validar-modo-sil.test.ps1
```

Para actualizar el codigo **despues de fusionar y con arbol de trabajo limpio**:

```powershell
git fetch origin
git switch develop
git pull --ff-only origin develop
```

No usar `docker compose down -v`, `git reset --hard` ni aplicar migraciones
para simplificar esta actualizacion. Una APK Android se construye aparte,
con la URL de su API autorizada y acceso privado a Tailscale cuando corresponda.

## 6. Limites

Estas verificaciones no sustituyen una auditoria de seguridad, ensayo de
rendimiento, validacion clinica o pruebas con dispositivos Android reales.
Tampoco comprueban los permisos efectivos del usuario PostgreSQL desplegado:
esa auditoria se planifica por separado y en modo solo lectura.

## 7. Cierre controlado de derivaciones pendientes (esquema 042)

La migracion `042_sil_main_pending_closure.sql` habilita que el operador
cierre una derivacion pendiente cuando esta duplicada, ilegible, retirada o
no corresponde. El cierre registra un motivo **codificado**, operador y fecha,
sin guardar datos clinicos de texto libre en el evento de auditoria.

- Solamente el operador asociado al laboratorio puede cerrar una pendiente.
- Una derivacion completada o cerrada no puede cerrarse nuevamente.
- Una derivacion cerrada no puede convertirse en orden ni descargarse por la
  ruta de trabajo pendiente. El PDF se conserva en PostgreSQL para trazabilidad.
- No existe reapertura automatica. La restriccion de duplicados por hash del
  documento se mantiene; un cierre no habilita reingresar la misma derivacion.
- `migrate-all` solo **verifica 042 en lectura**; no aplica cambios a `vitalia`.

**Despliegue:** se requiere respaldar y ensayar el esquema 041 en copia
aislada, comparar checksums del historial y autorizar de manera especifica
la migracion controlada 041 → 042. El pull request no modifica por si solo
el servidor local, Docker ni el volumen principal. No ejecutar
`migrate-main-sil --apply` sin completar el protocolo existente.

**Pruebas automáticas:** Jest verifica permisos, motivos, atomicidad y
auditoria; el recorrido CI en Edge/PostgreSQL temporal comprueba cierre,
ausencia de nuevas ordenes y bloqueo de finalizacion posterior.

## 8. Ciclo de vida de operadores por laboratorio (esquema 043)

El administrador puede suspender o reactivar el acceso de un operador al
laboratorio seleccionado mediante `POST /labs/:labId/staff/membership`.
El cambio es transaccional, exige el rol administrador, registra el actor
en auditoría y se limita a una membresía existente. No elimina cuentas,
contraseñas, documentos ni asociaciones en otros laboratorios.

Al suspender también se retira el permiso de revisión. Reactivar el acceso
**no** lo repone: el administrador debe otorgarlo explícitamente. Una cuenta
sin rol global activo de operador no puede reactivarse mediante esta ruta.
Las sesiones conservan su identidad, pero las operaciones en el laboratorio
quedan bloqueadas por la membresía inactiva.

La migración `043_sil_main_operator_membership.sql` sólo amplía los
eventos permitidos de auditoría y no reescribe registros anteriores.
La instalación en `vitalia` principal requiere respaldo, ensayo aislado
y aplicación explícita. No iniciar un backend nuevo contra un esquema
anterior a la versión requerida.


### Seguimiento administrativo de invitaciones y actividad

En **Operadores y permisos**, selecciona un laboratorio y abre **Ver invitaciones**.
La vista muestra invitaciones pendientes, activadas, vencidas o revocadas. El código
solo está disponible al emitir la invitación. Volver a emitir una invitación para
el mismo correo y laboratorio invalida la anterior.

En **Actividad**, abre **Ver auditoría administrativa** para consultar las
operaciones de laboratorio y operadores, con fecha y cuenta autora. Las consultas
requieren una sesión de administrador y se limitan al laboratorio seleccionado.
El recorrido automatizado usa cuentas ficticias para verificar paginación, separación
entre laboratorios y la exclusión de códigos y datos de auditoría internos.


En una invitación pendiente, **Revocar** pide confirmación y registra la acción en
la auditoría. La migración **044** amplía el catálogo de auditoría. La revocación
y su evento se guardan en la misma transacción. Si la base está en 041, el
migrador controlado verifica el historial y aplica 042, 043 y 044 en orden.


## 9. Acceso iniciado por el paciente (Camino B)

1. El paciente crea una cuenta e inicia sesión. Una cuenta recién creada no
   obtiene asociaciones ni informes de laboratorio.
2. Durante la verificación de identidad en el laboratorio, el paciente abre
   **Mi cuenta → Vincular mi cuenta** y genera un código. El código dura 15
   minutos, se muestra al emitirlo y reemplaza al anterior. Cada cuenta puede
   generar hasta tres códigos por hora.
3. El operador selecciona su laboratorio y abre **Pacientes → Vincular cuenta
   paciente**. Coteja la identidad mediante el procedimiento de la institución
   y registra una referencia sin datos clínicos, junto al código del paciente.
4. La API comprueba rol y membresía, consume el código una vez y registra la
   asociación y el evento de auditoría en una transacción. La inspección de
   identidad sigue siendo responsabilidad del laboratorio.

La migración **045** crea el registro de códigos. Conserva el hash, el
vencimiento, la cuenta emisora y el laboratorio que canjeó el código. El
recorrido automático verifica registro, expiración, reuso, separación entre
laboratorios y límites de emisión con cuentas ficticias.

## 10. Actualizar una instalación Windows a la versión integrada

Tras fusionar y desde un árbol limpio en `develop`, valida la configuración
y genera el respaldo antes de cambiar servicios.

```powershell
git pull --ff-only origin develop
.\deploy\validar-modo-sil.ps1
.\deploy\backup-main-before-sil.ps1
```

El script informa la ruta real del respaldo y su huella SHA-256.
**Registra la ruta exacta** que aparece después de «Destino:»; no uses
una ruta inventada ni el nombre de un respaldo anterior. Luego calcula
la huella del mismo archivo para el ensayo, en esta sesión de PowerShell:

```powershell
$backupFile = Read-Host 'Pega la ruta exacta indicada en Destino'
if (-not (Test-Path -LiteralPath $backupFile -PathType Leaf)) {
  throw 'No existe el respaldo indicado. No continuar.'
}
$backupSha256 = (Get-FileHash -LiteralPath $backupFile -Algorithm SHA256).Hash
if ($backupSha256.Length -ne 64) { throw 'SHA256 inválido. No continuar.' }
```

Comprueba que coincida con la huella impresa por el script de respaldo.
Compila la imagen nueva sin iniciar la API, y ensaya el migrador usando
el respaldo en un PostgreSQL aislado:

```powershell
docker compose build api
Push-Location backend
npm ci
npm run build
Pop-Location
.\deploy\rehearse-main-sil-migrations.ps1 -BackupFile $backupFile `
  -ExpectedSha256 $backupSha256 -UseBackendMigrator
```

Después de verificar el ensayo y obtener la aprobación local, detén la API y
el procesador durante el cambio de esquema. Ejecuta el migrador de la
imagen nueva y comprueba sus códigos de salida antes de seguir.

```powershell
docker compose stop api worker
docker compose run --rm --no-deps -T `
  -e VITALIA_MAIN_SIL_APPLY=CONFIRMED_AFTER_ISOLATED_TEST `
  -e "VITALIA_MAIN_BACKUP_SHA256=$backupSha256" `
  --entrypoint node api dist/database/migrate-main-sil.js --apply
docker compose run --rm --no-deps -T --entrypoint node api dist/database/migrate-all.js
```

Con el esquema verificado, recompila Flutter y levanta los servicios desde la
raíz. PostgreSQL mantiene el volumen existente.

```powershell
.\deploy\crear-web.ps1
docker compose --profile web up -d api worker web
Invoke-RestMethod http://127.0.0.1:5173/api/health
```

## 11. Trazabilidad del alcance postanalítico

| Requisito | Implementación | Evidencia automatizada |
| --- | --- | --- |
| Administrar operadores e invitaciones | Directorio, permisos, membresías, estados y revocación por laboratorio | Consultas, separación, paginación y revocación repetida en el recorrido SIL |
| Consultar auditoría administrativa | Actividad administrativa desde el rol administrador | Eventos y campos permitidos en el recorrido SIL |
| Recibir y cerrar derivaciones | Estación de recepción, extracción asistida y cierre transaccional 042 | PDF sintético, cierre y rechazo de conversión posterior |
| Revisar y publicar informes | Revisión por operador autorizado y confirmación de autorización externa | Flujo operador y descarga posterior por el paciente |
| Activar cuenta por invitación | Camino A con código de invitación y evidencia de identidad | Activación con cuenta ficticia y vinculación al laboratorio |
| Vincular cuenta iniciada por paciente | Camino B con verificación del operador y código 045 | Registro, expiración, reuso, membresía y límite de emisión |
| Consultar historial y ayuda | Portal Flutter, informes publicados y comparación descriptiva | Widgets de portal, comparación y descarga en Edge |

## Sedes del laboratorio (046)

En **Administración → Sedes**, selecciona el laboratorio y registra sus
ubicaciones. El nombre es único por laboratorio. El directorio de pacientes
solo muestra los datos de contacto de sedes activas de sus laboratorios.

Al guardar una derivación PDF o registrar una orden, una única sede activa se
selecciona automáticamente. Cuando hay varias, el operador elige una. Un
laboratorio sin sedes activas admite registros sin sede. Al vincular un PDF a
una orden existente se utiliza la sede de esa orden. Las órdenes antiguas
siguen siendo válidas y conservan su relación al desactivar una sede.

La migración `046_sil_main_laboratory_sites.sql` crea el catálogo y agrega
referencias opcionales con una clave compuesta por laboratorio y sede. Usa
el apartado de actualización de Windows y Docker para ensayar el salto
045 → 046 con el respaldo disponible. El verificador de arranque de la API
permanece en solo lectura y las sedes se crean desde administración.


En el portal, **Inicio** reúne saludo, cantidad total de informes, última
publicación, comparación y contacto. **Mis informes** permite buscar en los
documentos publicados del paciente por examen, folio o laboratorio, con
páginas de hasta 50. Los datos de sede de un informe se ven en **Más opciones**.

En **Sedes**, el encabezado identifica al laboratorio principal y cada sede
muestra dirección, región, comuna y datos de contacto. Al editar o registrar
una sede, el catálogo territorial de Vitalia habilita la comuna después de
elegir la región. Si se modifica la región o la comuna, se solicita de nuevo
la calle y el número. La API verifica el par región-comuna. La dirección
manual debe cotejarse con la ubicación real de la sede. Las sedes antiguas
con un territorio libre se pueden consultar y deben corregirse al editarlas.


## Asignación de operadores a sedes (047)

**Propósito.** El administrador registra un operador con **Agregar operador**, selecciona
el laboratorio y distingue entre un correo de operador nuevo (invitación de un solo uso)
o una cuenta de operador ya activa (vinculación directa). Antes de confirmar, elige
**Todas las sedes** o **Solo sedes seleccionadas**. Un operador puede tener una o varias
sedes del mismo laboratorio; ninguna sede de otro laboratorio puede asignarse.

- La invitación guarda el alcance escogido hasta su canje. Durante la activación se
  comprueba nuevamente que las sedes asignadas siguen activas.
- El directorio administrativo muestra el alcance de cada operador y permite
  modificarlo con **Asignar sedes**. La modificación se audita.
- Los operadores anteriores conservan acceso a todas las sedes dentro de los
  laboratorios donde ya tenían membresía, incluso si se crean nuevas sedes.
- **Solo sedes seleccionadas** limita la creación y visualización de órdenes,
  derivaciones pendientes, descarga de PDFs, revisión y publicación, y conteos
  del panel operativo. Las órdenes históricas sin sede no son accesibles a
  operadores restringidos. El administrador conserva el monitoreo general.
- Los pacientes asociados siguen formando parte del directorio compartido del
  laboratorio para permitir recibir nuevos requerimientos; esta función no
  restringe por sí sola el directorio de pacientes por sede.
- Una sede desactivada permanece en el historial, pero no se puede asignar en
  nuevas operaciones ni al modificar una asignación.

**Seguridad y despliegue:** la migración aditiva
`047_sil_main_staff_sites.sql` agrega el modo de acceso, las relaciones
operador-sede y la configuración de invitación. No elimina cuentas ni órdenes.
El backend requiere el esquema 047; `migrate-all` continúa validando solamente
en lectura. Para pasar de 046 a 047 se exige respaldo del entorno principal,
ensayo en PostgreSQL temporal, comprobación de checksum y autorización expresa
antes de ejecutar `migrate-main-sil --apply`.

Esta función no necesita Google Maps ni ninguna clave externa. La verificación
opcional de direcciones continúa separada de los permisos por sede.
