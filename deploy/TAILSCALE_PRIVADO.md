# Vitalia Health: acceso privado con Tailscale (equipo académico)

Este despliegue no es hosting público ni reemplaza a GitHub. La **misma** instancia de
Vitalia (frontend, API y PostgreSQL existentes en Docker) queda accesible únicamente
mediante Tailscale Serve. No se comparten archivos .env, contraseñas ni copias de BD.

## Preparación

- Instalar Tailscale en Windows: https://tailscale.com/docs/install/windows
- Iniciar sesión desde la aplicación de Tailscale. La cuenta y la red son del
  responsable de la máquina anfitriona.
- Invitar a los tres colaboradores de manera individual; idealmente compartir
  **solo este dispositivo** desde la consola de Tailscale y limitar sus accesos
  a HTTPS/443 mediante las reglas de acceso.
- **No habilitar Funnel**, ni reenviar puertos en el router, ni publicar
  PostgreSQL. El contenedor web y la API deben seguir enlazados a 127.0.0.1
  en compose.yaml.
- Usar solamente identidades, derivaciones e informes **ficticios**.

## Actualización segura en el PC anfitrión (PowerShell)

Desde una rama local que siga a `feat/sil-integracion-vitalia-principal`
sin cambios versionados sin guardar:

```powershell
cd C:\Users\dpalm\Documents\vitalia-health-git

if ((@(git status --porcelain --untracked-files=no)).Count -gt 0) {
  throw "Hay cambios locales versionados. Revisa antes de continuar."
}
git fetch origin feat/sil-integracion-vitalia-principal
if ($LASTEXITCODE -ne 0) { throw "git fetch falló" }
git switch feat/sil-integracion-vitalia-principal
if ($LASTEXITCODE -ne 0) { throw "git switch falló" }
git pull --ff-only origin feat/sil-integracion-vitalia-principal
if ($LASTEXITCODE -ne 0) { throw "git pull falló" }

cd apps\vitalia
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get falló" }
flutter build web --release --no-web-resources-cdn `
  --dart-define=VITALIA_SIL_MAIN_MODE=true `
  --dart-define=VITALIA_API_SAME_ORIGIN=true
if ($LASTEXITCODE -ne 0) { throw "flutter build web falló" }

cd ..\..
docker compose --profile web up -d --force-recreate --no-deps web
if ($LASTEXITCODE -ne 0) { throw "No fue posible actualizar Nginx" }
docker compose exec web nginx -t
Invoke-RestMethod http://localhost:5173/api/health
```

`Invoke-RestMethod` debe devolver el servicio Vitalia con estado `ok`.
Si algo falla, detenerse y diagnosticar antes de habilitar Serve.

El modo `VITALIA_API_SAME_ORIGIN=true` hace que el navegador consuma
`/api/...` desde el origen del sitio web actual, tanto si es localhost
como si es el dominio HTTPS privado. Nginx proxifica internamente /api/
hacia el backend Docker. No se habilita CORS abierto.

## Publicación privada

Con PowerShell **como administrador** y Tailscale iniciado:

```powershell
tailscale status
tailscale serve --bg http://127.0.0.1:5173
tailscale serve status
```

Si Tailscale solicita configurar certificados HTTPS o autorizar Serve,
completar esa autorización desde el navegador. Tailscale mostrará una
dirección HTTPS del tipo `https://nombre-equipo.nombre-red.ts.net`;
**no inventar** la dirección: usar exclusivamente la que informe Serve.

Enviar esta dirección **en privado** a los compañeros autorizados.
Podrán abrir las rutas de Vitalia (por ejemplo, `/#/laboratorio`) desde
su Edge y acceder con cuentas de prueba propias asignadas por rol.

## Seguridad y operación

- El PC anfitrión debe permanecer encendido con Docker y Tailscale activos.
- GitHub permite editar código, pero **no despliega automáticamente** cambios:
  integrar PRs y reconstruir `flutter build web` cuando corresponda.
- No compartir contraseña de administrador ni reutilizar una única cuenta para
  múltiples personas. La auditoría debe asociar acciones a usuarios concretos.
- El acceso por Tailscale no reemplaza las autorizaciones de Vitalia.
- No compartir el enlace con personas que no tengan acceso autorizado.
- Comprobar las ACL o grants de Tailscale: los invitados deben alcanzar como
  máximo el servicio HTTPS necesario, no servicios personales del anfitrión.
- La emisión de HTTPS de Tailscale puede registrar públicamente **el nombre
  del equipo y de la red** en registros de transparencia de certificados;
  elegir nombres no sensibles antes de habilitar HTTPS.
- No utilizar `tailscale funnel`: Funnel expone servicios públicamente.

Para desconectar sin borrar la base de datos:

```powershell
tailscale serve --https=443 off
tailscale serve status
```

Referencias oficiales:
- https://tailscale.com/docs/features/tailscale-serve
- https://tailscale.com/docs/reference/tailscale-cli/serve
- https://tailscale.com/docs/features/sharing
- https://tailscale.com/docs/how-to/set-up-https-certificates
