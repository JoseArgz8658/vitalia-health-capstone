# Sesiones y API de acceso — fase 3.6

Rama fase-3/sesiones-acceso. Requiere PostgreSQL 16 local, .env privado y la migración 001_accounts aplicada.
No hay dependencias nuevas ni cambios a .env o package-lock.json.
Los únicos archivos existentes modificados son app.ts y server.ts, autorizados por el usuario; registro CAM-004.
Flutter conserva su pantalla anterior. No hay registro público ni cuentas permanentes precreadas.

## 1. Obtener y comprobar el código
Desde la raíz del repositorio, guarda cambios propios si git status los muestra:
```powershell
git fetch origin
git switch fase-3/sesiones-acceso
cd backend
npm ci
npm run check
npm test
```
Esperado: 11 suites y 61 pruebas aprobadas. npm test también compila.

## 2. Comprobar PostgreSQL y aplicar sesiones
Con PostgreSQL activo, desde backend:
```powershell
node --env-file=.env dist/database/check.js
node --env-file=.env dist/database/migrate-sessions.js
```
Continúa al segundo comando solo si el primero confirma conexión.
Resultado esperado:
```text
Migración de sesiones aplicada.
```
Repetir el comando debe responder La migración de sesiones ya estaba aplicada.
Esta migración agrega public.vitalia_sessions y su registro de versión. No modifica la migración anterior ni borra cuentas.
Si falta 001_accounts, ejecuta primero la guía docs/cuentas-postgresql.md. No borres tablas para reintentar una migración fallida.

## 3. Prueba real de API con datos sintéticos
```powershell
node --env-file=.env dist/database/verify-auth-api.js
```
Resultado esperado:
```text
API de acceso correcta: login, sesión, expiración y logout. Datos sintéticos revertidos.
```
La prueba abre su propio servidor en un puerto libre de loopback. No necesitas npm start para ejecutarla.
Guarda una cuenta sintética dentro de una transacción. Prueba acceso sin sesión, contraseña incorrecta, login correcto, huella almacenada, consulta de identidad, logout, nuevo token y expiración.
Revierte la transacción y verifica que no queden la cuenta ni sus sesiones. No imprime credenciales ni tokens.
La prueba no comprueba la duración real de 30 minutos mediante una espera: cambia solo las fechas de su propia sesión sintética dentro de la transacción para verificar el rechazo por expiración.

## 4. Arrancar el servidor habitual
```powershell
npm start
```
Debe mostrar Vitalia API iniciada en el entorno local.
Abre http://127.0.0.1:3000/api/health para comprobar la respuesta anterior.
Al detenerlo con Ctrl+C, el servidor cierra HTTP y sus conexiones PostgreSQL. Da hasta diez segundos a conexiones HTTP pendientes antes de cerrarlas.
Ahora el arranque exige .env válido, PostgreSQL disponible y las tablas de cuentas y sesiones. Si falta alguno, falla de forma controlada sin exponer valores.
Para verificar desde otro PowerShell, sin credenciales:
```powershell
try {
  Invoke-WebRequest -Uri http://127.0.0.1:3000/api/auth/me
} catch {
  [int]$_.Exception.Response.StatusCode
}
```
Debe mostrar 401. No significa fallo del servidor: esa consulta no tiene sesión.
Aún no hay cuenta permanente para probar login manualmente. No introduzcas cuentas reales ni credenciales en comandos, capturas o archivos versionados.

## Contrato actual
| Método | Ruta | Resultado |
| --- | --- | --- |
| POST | /api/auth/login | Correo/contraseña correctos → token, expiresAt y resumen de usuario |
| GET | /api/auth/me | Authorization: Bearer TOKEN válido → resumen de identidad |
| POST | /api/auth/logout | Revoca el token recibido; 204 si su formato es válido |
| GET | /api/health | Disponibilidad del proceso Express |

Login acepta exclusivamente email/password. El servicio rechaza otros campos y nunca usa un rol enviado por el cliente.
Credenciales incorrectas devuelven 401 con un mensaje neutral. me devuelve 401 si falta el token o no existe una sesión vigente. Fallos internos devuelven 500 sin detalles. Si el cálculo de credenciales está ocupado, responde 503 con Retry-After.
Las respuestas de auth usan Cache-Control: no-store.
Logout es idempotente para tokens con formato válido: responde 204 incluso si ya fueron revocados, sin informar su existencia.

## Sesiones y límites
Token opaco de 32 bytes aleatorios, representado como 64 caracteres hexadecimales. PostgreSQL guarda solo SHA-256 del token y no el token original.
Expiración absoluta de 30 minutos, sin renovación automática. Son valores iniciales de implementación; no un requerimiento nuevo de negocio.
El rol se consulta desde la cuenta en cada acceso a me, sin confiar en datos del cliente.
El límite local cuenta diez peticiones login por dirección y ventana de quince minutos, exitosas o fallidas. La petición siguiente responde 429. No confía en X-Forwarded-For. El mapa tiene un máximo de mil direcciones.
El límite vive en un proceso y se reinicia con el servidor. Antes de desplegar con proxy o varias instancias habrá que configurar un límite compartido y la política de proxy. Actualmente no se habilita trust proxy.
Las filas expiradas dejan de autenticar aunque aún permanezcan almacenadas. Su limpieza y política de retención quedan pendientes.
El uso de bearer permite una API común para móvil/web. La integración Flutter no está hecha y el almacenamiento del token del lado cliente se definirá en esa fase; no se debe poner en URLs ni repositorios.
El desarrollo funciona en loopback local; un despliegue real requerirá HTTPS y controles de permisos por recurso. me acredita identidad, pero no implementa todavía la autorización de exámenes ni administración.

## Servicio detenido
Si Get-Service postgresql-x64-16 muestra Stopped, abre PowerShell como administrador y ejecuta Start-Service postgresql-x64-16. Confirma Running y vuelve a la terminal habitual en backend.
Si algún paso falla, comparte solo mensajes y códigos de salida, nunca .env, contraseña o token.
