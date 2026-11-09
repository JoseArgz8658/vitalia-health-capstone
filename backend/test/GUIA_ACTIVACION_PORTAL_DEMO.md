# Vitalia Health — Activación privada de pacientes (SIL DEMO)

## 1. Alcance seguro de esta iteración

Esta implementación es **exclusivamente ficticia y local**. No usa números de
documento, identificadores reales ni información de salud real. No envía correos
electrónicos reales: el correo se simula en memoria del proceso
`vitalia-sil-demo` y el acceso al buzón sólo se expone cuando este ejecutable
aislado habilita `VITALIA_SIL_DEV_MAILBOX=YES`.

La pantalla muestra un destinatario completo ANTES de enviar la invitación:
nombre, apellidos, identificador sintético, fecha de nacimiento y correo.
Dos confirmaciones independientes del operador son obligatorias. Es una
**declaración manual**, no una comprobación automatizada de identidad.

Un paciente DEMO nuevo se registra primero con una credencial aleatoria
inaccesible al operador. **No puede iniciar sesión** antes de activar su acceso.
La contraseña final es creada solamente por el paciente. Una cuenta legada,
como `paciente.sil@example.invalid`, conserva sus credenciales y NO puede
reiniciarse mediante este flujo. El historial de órdenes queda vinculado al
mismo UUID interno y no se reasigna.

## 2. Cambios técnicos

- Migración aditiva `036_sil_portal_invites_demo`: accesos, invitaciones
  con tokens hasheados y eventos de auditoría independientes.
- Rutas bajo `/api/sil/portal`: alta, destinatario, invitaciones,
  buzón ficticio y activación.
- Códigos aleatorios de 12 caracteres generados criptográficamente para
  email y entrega presencial; hash SHA-256 en PostgreSQL, vigencia de
  20 minutos, cinco intentos máximos, tres invitaciones por hora y uso único.
- La invitación previa se revoca al reenviar. Al activar se configura una
  contraseña propia mediante scrypt, se invalidan sesiones anteriores y se
  registra el evento. Nunca se almacena contraseña sin hash.
- El código de email **nunca se devuelve** al operador. El segundo código
  se muestra una sola vez para su entrega por un canal distinto.
- No se envían resultados, órdenes, RUN ni diagnósticos por correo; el
  contenido simulado sólo explica cómo activar el acceso.
- La interfaz utiliza un asistente animado de tres pasos y un panel
  contextual con estado, fechas de confirmación y destinatario.
- Rutas de órdenes, muestras, reportes y revisión originales permanecen
  intactas. La ampliación no cambia el modelo de extracción de IA.

## 3. Verificar rama y compilar ANTES de desplegar

Desde `C:\Users\dpalm\Documents\vitalia-health-git`:

```powershell
git status --short
git fetch origin
git switch -c feat/sil-portal-activacion-demo --track origin/feat/sil-portal-activacion-demo
npm --prefix backend run check
npm --prefix backend test
cd apps\vitalia
flutter analyze lib/features/acceso/activar_portal_sil_page.dart lib/features/laboratorio/acceso_portal_paciente_demo.dart lib/features/laboratorio/nuevo_paciente_sil_dialog.dart lib/features/laboratorio/directorio_pacientes_sil.dart lib/features/laboratorio/operador_laboratorio_page.dart
flutter test test/activar_portal_sil_test.dart
flutter test
flutter build web
cd ..\..
```

**Detenerse ante cualquier fallo.** El aviso sobre actualización de Flutter no
es requisito para esta iteración. No usar `git reset --hard` ni `git clean`
para cambiar de rama si hay archivos sin guardar.

## 4. Aplicar SOLAMENTE la migración aislada (tras pruebas)

Sólo si está verificado el contenedor `vitalia-postgres-sil-persistent`, la
red `vitalia-fase7-test-net` y `vitalia_dev`. El comando invoca el
migrador existente, que aplica únicamente migraciones pendientes. **No usar
el PostgreSQL principal** ni ejecutar un `docker compose down -v`.

```powershell
cd C:\Users\dpalm\Documents\vitalia-health-git
$distPath=(Resolve-Path ".\backend\dist").Path
$migrationsPath=(Resolve-Path ".\backend\database\migrations").Path
try {
  $env:PGPASSWORD=(docker exec vitalia-postgres-sil-persistent printenv POSTGRES_PASSWORD).Trim()
  docker run --rm --network vitalia-fase7-test-net `
    --mount "type=bind,source=$distPath,target=/app/dist,readonly" `
    --mount "type=bind,source=$migrationsPath,target=/app/database/migrations,readonly" `
    --env PGPASSWORD --env PGHOST=postgres --env PGPORT=5432 `
    --env PGDATABASE=vitalia_dev --env PGUSER=vitalia `
    --env VITALIA_RUNTIME=container --entrypoint node `
    vitalia-backend:local dist/database/migrate-all.js
  if($LASTEXITCODE -ne 0){throw "Falló la migración del portal DEMO."}
} finally {
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
```

La migración `036` crea tablas nuevas. No modifica datos de fichas,
credenciales ni órdenes existentes.

```powershell
docker restart vitalia-sil-demo
Invoke-RestMethod http://127.0.0.1:3101/api/health
docker logs --tail 12 vitalia-sil-demo
```

Se espera `status: ok`, `service: sil-demo-only`. Si aparece un error de
migración, no recrear contenedores; revisar el paso anterior y compartir
el mensaje sin contraseñas.

## 5. Probar Flutter con el servidor correcto

```powershell
cd apps\vitalia
flutter run -d edge --web-hostname localhost --web-port 5173 `
  --dart-define=VITALIA_API_URL=http://127.0.0.1:3101 `
  --dart-define=VITALIA_SIL_DEMO_MODE=true
```

### Operador
1. Ingresar en `http://localhost:5173/#/laboratorio` como
   `operador.sil@example.invalid`.
2. **Pacientes → Nuevo paciente DEMO**: introducir datos inventados y correo
   `nuevo-paciente-demo@example.invalid`. No se envían mensajes todavía.
3. Abrir su ficha. En **Acceso al portal**, comprobar que figura
   `Sin activar`; revisar nombre, identificador, fecha de nacimiento y email.
4. Pulsar **Preparar invitación DEMO** y marcar las dos confirmaciones
   manuales. El operador recibe únicamente la **clave presencial** (una vez).
5. El estado pasa a `Invitación pendiente` y muestra la caducidad.

### Paciente
1. En otra ventana (puede ser privada), abrir
   `http://localhost:5173/#/activar-portal`.
2. Ingresar el correo ficticio anterior. En el segundo paso pulsar
   **Abrir buzón ficticio de prueba** para consultar el correo simulado.
3. Copiar el código de correo en su campo. Introducir la clave presencial
   obtenida por el operador **en otro campo**.
4. Crear una contraseña propia de al menos 12 caracteres y confirmar
   que los datos corresponden a esa cuenta DEMO.
5. Finalizada la activación, usar
   `http://localhost:5173/#/informes` e iniciar sesión con ese correo y
   su nueva contraseña. Sin reportes publicados, verá el portal vacío; eso
   es correcto y evita simular informes clínicos.

### Pruebas negativas
- Código distinto, expirado, consumido o quinto intento fallido: denegado.
- Reenvío: invalida el anterior, máximo tres envíos por hora.
- Cuenta anterior ya activa: el módulo no cambia su contraseña.
- Sin inicio de sesión de operador: no puede ver destinatarios ni crear
  invitaciones.
- PDF ni informe se incluye en correo; la activación no publica documentos.

## 6. Lo que NO debe confundirse con un servicio listo para producción

El buzón de demostración es visible a quien conoce el correo ficticio desde
la API local y por ello **nunca debe habilitarse con pacientes reales o acceso
remoto**. Antes de ofrecer Vitalia comercialmente hay que sustituirlo por un
servicio de correo autenticado (con dominio verificado, DKIM/SPF, reintentos,
límite de entregas, rebotes y baja de notificaciones cuando proceda).
También se necesita un modelo definitivo que separe ficha clínica y cuenta
web, vinculación por identidad verificada, aislamiento por laboratorio,
permisos mínimos por contexto asistencial, revisión legal, retención segura
y un mecanismo de recuperación de contraseña. Una casilla marcada por el
operador no acredita identidad por sí sola.

**No integrar en una rama de producción ni almacenar datos reales hasta
completar estas condiciones.**
