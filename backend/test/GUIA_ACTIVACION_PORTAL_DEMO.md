# Vitalia Health — Activación privada de pacientes (SIL DEMO)

## 1. Alcance seguro de esta iteración

Esta implementación es **exclusivamente ficticia y local**. No usa números de
documento, identificadores reales ni información de salud real. No envía correos
electrónicos reales: el correo se simula en memoria del proceso
`vitalia-sil-demo` y el acceso al buzón sólo se expone cuando este ejecutable
aislado habilita `VITALIA_SIL_DEV_MAILBOX=YES`.

El buzón está en memoria: si se reinicia el contenedor durante una
invitación, el correo simulado desaparece. El operador puede emitir una
invitación nueva (con los límites indicados), que invalida la anterior.

La pantalla muestra un destinatario completo ANTES de enviar la invitación:
nombre, apellidos, identificador sintético, fecha de nacimiento y correo.
Dos confirmaciones independientes del operador son obligatorias. Si el
destinatario cambia antes de emitir la invitación, se debe consultar la ficha y
confirmar nuevamente. Es una
**declaración manual**, no una comprobación automatizada de identidad.

Un paciente DEMO nuevo se registra primero con una credencial aleatoria
inaccesible al operador y el **rol paciente inactivo** en la tabla de permisos.
**No puede iniciar sesión** antes de activar su acceso. El rol se habilita
únicamente al verificar ambos canales y guardar la contraseña definitiva.
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
git switch --track origin/feat/sil-paciente-portal
npm --prefix backend run check
npm --prefix backend test
cd apps\vitalia
flutter analyze
flutter test --dart-define=VITALIA_SIL_DEMO_MODE=true test/paciente_portal_sil_test.dart test/activar_portal_sil_test.dart
flutter test
flutter build web --dart-define=VITALIA_API_URL=http://127.0.0.1:3101 --dart-define=VITALIA_SIL_DEMO_MODE=true
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
    --env VITALIA_RUNTIME=container --env VITALIA_SIL_PORTAL_MIGRATION_DEMO=YES --entrypoint node `
    vitalia-backend:local dist/database/migrate-all.js
  if($LASTEXITCODE -ne 0){throw "Falló la migración del portal DEMO."}
} finally {
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
```

Las migraciones `036` y `037` son optativas. El migrador general las omite si no se especifica
`VITALIA_SIL_PORTAL_MIGRATION_DEMO=YES` y rechaza ese permiso para una base
distinta de `vitalia_dev`. Ambas migraciones crean tablas nuevas.

El arranque comprueba las claves configuradas del operador y del administrador.
La clave configurada del paciente de ejemplo se usa para su alta inicial. Su
contraseña vigente se conserva aunque la recupere y se reinicie la demo.

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

### Registro web independiente y recuperación

1. Desde el acceso de paciente, usa **Crear cuenta de paciente** con un correo
   ficticio nuevo. El registro web crea una cuenta sin ficha vinculada. Si el
   correo ya existe, la respuesta es genérica y se conserva la cuenta existente.
2. Entra a **Mis informes** con el nuevo correo. El portal consulta informes
   autorizados de esa cuenta y permite buscar en los 50 más recientes.
3. Abre **Configurar recuperación**, confirma tu contraseña actual y guarda
   la clave en un lugar privado. La clave se muestra una vez, vence a los 90
   días y una clave nueva reemplaza a la anterior.
4. Cierra sesión y elige **Olvidé mi contraseña**. Completa el correo, la clave
   de respaldo y la nueva contraseña. Después, ingresa con la nueva clave.
   La recuperación invalida las sesiones de paciente anteriores y registra
   el evento sin almacenar el código ni la contraseña en la auditoría.
5. Prueba repetir el restablecimiento con la clave consumida y con la
   contraseña anterior. Ambos intentos deben rechazarse. Para cuentas sin
   una clave de respaldo vigente, corresponde contactar al laboratorio.

### Preguntas abiertas del asistente

Abre **Preguntar sobre el informe** y escribe o modifica una pregunta, por
ejemplo «q es la glicemia», «¿Qué significa rango de referencia?» o
«Explícame qué miden estas pruebas». Contrasta con «¿Está alta mi glicemia?»
o «Muéstrame el informe de otro paciente». Cada consulta se resuelve por
separado. El modelo local solo recibe los nombres de las prestaciones
autorizadas y la pregunta. Para cifras y observaciones consulta el PDF.
La batería `test/sil-patient-education.test.cjs` comprueba el catálogo,
el contrato del modelo y casos sintéticos de seguridad. Estos ajustes son
instrucciones y evaluación de prompts para el modelo local.

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
