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

La rama de trabajo integrada es `develop`, no la antigua
`feat/sil-integracion-vitalia-principal`. Consultar primero
[Operación segura del SIL principal](../docs/OPERACION_SIL_PRINCIPAL.md):
contiene el preflight, requisitos del esquema **041**, compilación web
con same-origin y verificación de la ruta principal.

**Antes de cualquier despliegue:** revisar que el backend ya ejecute
`VITALIA_SIL_MAIN_MODE=YES` y que la base principal esté correctamente
integrada. `deploy/crear-web.ps1` ahora comprueba `.env` antes de compilar;
nunca aplica migraciones ni modifica Docker. Si falla, se detiene la operación
sin cambiar la instancia.

```powershell
# Solo después de integrar un PR y con el árbol local sin cambios pendientes.
git fetch origin
git switch develop
git pull --ff-only origin develop

powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\validar-modo-sil.ps1
# Compilación local (no despliega ni reinicia contenedores).
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\crear-web.ps1
```

Para publicar la compilación debe existir autorización expresa del equipo
y seguirse el apartado de actualización web de la guía anterior. No se
destruyen volúmenes, ni se reinicia PostgreSQL ni se habilita Funnel.

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
