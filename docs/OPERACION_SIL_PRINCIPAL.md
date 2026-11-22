# Operacion segura del SIL principal — Vitalia Health

Esta guia corresponde a la rama integrada `develop`. El SIL principal gestiona
solicitudes, ordenes, revision y publicacion de informes ya autorizados, con datos
**sinteticos**. No usar esta guia para operar con datos clinicos reales.

## 1. Condiciones antes de compilar o desplegar

El backend usa la base principal `vitalia`, esquema postanalitico **043** una vez aplicado mediante el procedimiento controlado (la instalacion 041 existente no se modifica automaticamente)
integrado mediante el procedimiento controlado. El codigo distingue:

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
`migrate-all` solo verifica el esquema; **no aplica** las migraciones 041, 042 ni 043.
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
las migraciones SIL hasta la 043 y la tabla de derivaciones pendientes con cierre administrativo.
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
