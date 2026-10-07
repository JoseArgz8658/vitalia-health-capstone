# Vitalia Health — instalación y uso

La idea de esta rama es que podamos descargar el proyecto y probarlo en otro equipo, tanto en web como en Android, sin llevarnos los documentos de avance ni las pruebas manuales de etapas anteriores. Aquí está la aplicación Flutter, el backend, las migraciones y lo necesario para levantar el entorno.

El proyecto permite registrar pacientes, subir documentos, solicitar su extracción, revisar los datos como profesional y hacer preguntas sobre el examen revisado. Las respuestas de IA no son diagnósticos, recetas ni aprobación profesional. Para las pruebas usemos documentos ficticios.

Docker prepara el backend, PostgreSQL y Ollama en contenedores. No instala Android Studio ni crea un emulador. Tampoco incluye las credenciales de AWS: S3 sigue siendo un servicio externo. Cada equipo tiene su propia base de datos; descargar el proyecto no copia las cuentas que creó José.

## 1. Qué necesitamos instalar

| Herramienta | Cuándo es necesaria | Descarga y versión |
| --- | --- | --- |
| Docker Desktop | Obligatorio para el camino Docker; opcional para el camino local | [Descargar](https://docs.docker.com/desktop/setup/install/windows-install/). En Windows, usar contenedores Linux con WSL 2. |
| Flutter SDK | Obligatorio para ejecutar o compilar esta web y Android | [Instalar Flutter](https://docs.flutter.dev/install), [archivo de versiones](https://docs.flutter.dev/install/archive). Versión usada en el equipo de desarrollo: stable 3.44.6. |
| Android Studio | Obligatorio si usaremos un emulador Android; no hace falta para web | [Descargar](https://developer.android.com/studio), [configurar Flutter para Android](https://docs.flutter.dev/platform-integration/android/setup). |
| Node.js | Obligatorio en ejecución local y pruebas sin Docker; no hace falta en el equipo para levantar el backend con Docker | [Descargar Node.js](https://nodejs.org/es/download). Usar Node 24 LTS. Docker usa 24.21.0. |
| PostgreSQL | Obligatorio instalado en el equipo solo para el camino local | [Descargar](https://www.postgresql.org/download/windows/). Usar PostgreSQL 16; Docker lo incluye. |
| Ollama | Obligatorio instalado en el equipo solo para IA en el camino local | [Descargar](https://ollama.com/download). Docker lo incluye. Modelo: qwen3:4b-instruct. |
| Visual Studio Code | Opcional; recomendado para abrir y modificar el código | [Descargar](https://code.visualstudio.com/download). Extensiones Flutter y Dart. VS Code no es Visual Studio. |
| Git o GitHub Desktop | Opcional si descargamos ZIP; necesario para trabajar con ramas y subir cambios | [Git](https://git-scm.com/downloads), [GitHub Desktop](https://desktop.github.com/download/). |
| Acceso autorizado a AWS S3 | Obligatorio para el flujo real de documentos, con Docker o sin él | [Consola S3](https://console.aws.amazon.com/s3/). Bucket privado y credenciales propias/autorizadas. |

Para este entorno recomiendo 16 GB de RAM y espacio libre para Docker, el modelo y el emulador. Es una recomendación del proyecto, no una garantía de funcionamiento en cualquier computador. La IA puede ser más lenta en CPU y tiene límite de tiempo. Una GPU NVIDIA compatible ayuda; no es obligatoria para arrancar Docker. Una primera instalación requiere Internet para descargar dependencias e imágenes. S3 requiere conexión también durante el uso.

En Windows, si Docker pide WSL, abre PowerShell como administrador y ejecuta:

```powershell
wsl --install
wsl --update
```

Reinicia si lo solicita. Abre Docker Desktop y espera a que el motor esté funcionando. Luego, en una terminal nueva:

```powershell
docker --version
docker compose version
flutter --version
```

Si un comando no se reconoce, revisa su instalación y PATH y abre otra terminal. No necesitamos Visual Studio con C++ para probar web o Android.

## 2. Descargar y abrir el proyecto

En GitHub selecciona la rama de aplicación que corresponda, pulsa Code → Download ZIP y extrae el contenido. También puedes clonar el repositorio del equipo:

```powershell
git clone https://github.com/JoseArgz8658/vitalia-health-capstone.git
cd vitalia-health-capstone
git switch develop
```

Estos comandos de `develop` se usan después de que José haya copiado y publicado la aplicación en esa rama del repositorio oficial. Mientras tanto, descarga la rama `distribucion/equipo-docker` del repositorio de pruebas.

Abre la carpeta donde están `compose.yaml`, `README.md`, `backend` y `apps`. Esa es la raíz del proyecto. Todos los comandos siguientes parten desde ahí, salvo cuando se indica `cd backend` o `cd apps\vitalia`.

## 3. Preparar S3

Antes de iniciar la API necesitamos una región, un bucket y credenciales autorizadas para ese bucket. Docker no crea recursos de AWS ni transfiere los del desarrollador.

Si el equipo ya te proporcionó acceso a un bucket de pruebas, usa tus credenciales autorizadas. No copies credenciales de otra persona del repositorio. Si crearás el tuyo:

1. En la consola de AWS abre S3 → Create bucket.
2. Selecciona un bucket de propósito general y una región; por ejemplo, `us-east-2`.
3. El nombre debe ser único. Escríbelo sin espacios; evita poner datos personales.
4. Conserva **Block all public access** activado y **Object Ownership: Bucket owner enforced**, con ACL deshabilitadas.
5. Usa cifrado SSE-S3 y crea el bucket.
6. Pide al administrador de tu cuenta un acceso programático con permisos para el bucket de pruebas. Si tu cuenta institucional prohíbe crear usuarios o claves, esa restricción no se soluciona con Docker.

Los permisos usados por la aplicación son: `s3:ListBucket`, `s3:GetBucketPublicAccessBlock`, `s3:GetBucketOwnershipControls`, `s3:GetBucketPolicyStatus` sobre ese bucket, y `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` sobre su prefijo `patients/*`. El administrador debe limitar la política al ARN de ese bucket. [Guía oficial de creación](https://docs.aws.amazon.com/AmazonS3/latest/userguide/create-bucket-overview.html) y [bloqueo público](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html).

Necesitarás AWS Access Key ID y AWS Secret Access Key. Si son credenciales temporales, también AWS Session Token; cuando caduquen hay que renovarlas. No se incluyen en esta rama. Los recursos de AWS pueden tener costo según la cuenta y su uso.

## 4. Camino recomendado: servicios con Docker

### Crear la configuración

Desde la raíz, en PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\configurar.ps1 -Modo Docker
```

El script pide los datos de AWS, oculta los secretos y crea un `.env` local. La contraseña de la base Docker se genera automáticamente. Si el archivo ya existe, no lo reemplaza. No hay un `.env.example` en la rama de distribución: este script prepara la configuración necesaria.

No subas ese `.env` a GitHub ni lo compartas. El proyecto lo ignora. Para otro sistema operativo puedes crear un `.env` desde tu editor con estas variables: `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `AWS_REGION`, `S3_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y, si corresponde, `AWS_SESSION_TOKEN`. Usa una base/usuario llamado `vitalia`, contraseña propia y valores entre comillas simples. PowerShell 7 también permite ejecutar el script en macOS/Linux: `pwsh -File ./deploy/configurar.ps1 -Modo Docker`.

### Iniciar la base y descargar el modelo

```powershell
docker compose up -d postgres ollama
docker compose exec ollama ollama pull qwen3:4b-instruct
docker compose exec ollama ollama list
```

Espera a que termine la descarga. Ollama dentro de Docker guarda sus modelos en un volumen propio; no utiliza automáticamente los que ya tienes instalados en Windows.

### Iniciar API y procesador

Si tienes `npm start`, `npm run worker` o Flutter web abiertos de una prueba local anterior, detén esas terminales con Ctrl+C antes de utilizar los mismos puertos.

```powershell
docker compose up -d --build api worker
docker compose ps -a
docker compose logs --tail 40 migrate api worker
```

`migrate` aplica las migraciones en orden; debe terminar con código 0. API y worker arrancan después. La base, las cuentas y la conversación permanecen en el volumen local. La API debe indicar que inició y el worker que el procesador automático está activo. PostgreSQL y Ollama no tienen puertos publicados al exterior; la API se publica solamente en `127.0.0.1:3000`.

El procesador toma las solicitudes pendientes de la aplicación, de una en una. Debes seguir pulsando el botón para solicitar extracción: subir el archivo por sí solo no autoriza su procesamiento. El original de S3 se conserva y los datos extraídos quedan pendientes de revisión profesional.

Si el procesador se interrumpe y se reinicia, marca el trabajo que quedó en proceso como fallido. No lo vuelve a enviar automáticamente a la IA ni altera una revisión aprobada. Para repetir una prueba, sube una copia ficticia nueva y solicita la extracción. Los trabajos fallidos o rechazados no se repiten indefinidamente.

### GPU NVIDIA, opcional

En Windows necesitas Docker con WSL 2 y controladores NVIDIA compatibles. En Linux necesitas el NVIDIA Container Toolkit. [Guía Docker para GPU](https://docs.docker.com/compose/how-tos/gpu-support/) y [GPU en Windows](https://docs.docker.com/desktop/features/gpu/).

Para usar la configuración GPU desde el principio, reemplaza los comandos de `up` anteriores por:

```powershell
docker compose -f compose.yaml -f compose.gpu.yaml up -d postgres ollama
docker compose exec ollama ollama pull qwen3:4b-instruct
docker compose -f compose.yaml -f compose.gpu.yaml up -d --build api worker
```

Si tu equipo no tiene una GPU compatible, usa el camino normal con CPU. No habilites la configuración GPU sin soporte en tu equipo.

## 5. Verlo en web

Elige una de estas dos opciones; ambas utilizan la API de Docker o la API local en el mismo puerto.

### Web de desarrollo con Flutter

En otra terminal:

```powershell
cd apps\vitalia
flutter pub get
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

Se abrirá Edge. La URL es `http://localhost:5173`. Mantén abierta la terminal de Flutter. Usa siempre ese nombre y puerto: el backend restringe el origen web. En macOS/Linux usa `-d chrome` si tienes Chrome instalado.

### Web compilada servida por Docker

Desde la raíz, con Flutter instalado:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\crear-web.ps1
docker compose --profile web up -d web
```

Abre `http://localhost:5173`. Para recompilar después de cambios, repite el script. No ejecutes simultáneamente Flutter de desarrollo y el servicio `web`: ambos usan el puerto 5173. Si no usas PowerShell, el equivalente es `cd apps/vitalia`, `flutter pub get`, `flutter build web --dart-define=VITALIA_API_URL=http://127.0.0.1:3000`, volver a la raíz y ejecutar Compose.

## 6. Probar Android con emulador

1. Instala Android Studio y ejecuta su asistente inicial.
2. Abre SDK Manager e instala el SDK que indique `flutter doctor`, Android SDK Platform-Tools, Command-line Tools y Android Emulator.
3. En Device Manager → Create Virtual Device elige **Pixel 3a** o **Pixel 6**. Pixel 3a sirve para probar una pantalla pequeña; Pixel 6 ofrece otra resolución. No es necesario un emulador de televisión.
4. Recomiendo una imagen estable **Android 15 / API 35** para la prueba inicial, y después probar también API 36. En un PC Intel/AMD elige x86_64; en un equipo ARM elige una imagen compatible con su arquitectura. Estas son recomendaciones de prueba, no requisitos del nombre del teléfono.
5. Descarga la imagen y arranca el emulador. [Guía oficial de dispositivos virtuales](https://developer.android.com/studio/run/managing-avds).
6. En una terminal nueva:

```powershell
cd apps\vitalia
flutter doctor --android-licenses
flutter doctor
flutter pub get
flutter devices
```

Si aparece `emulator-5554`, ejecuta:

```powershell
flutter run -d emulator-5554 --dart-define=VITALIA_API_URL=http://10.0.2.2:3000
```

Si el identificador es otro, utiliza el que te mostró `flutter devices`. `10.0.2.2` permite al emulador llegar al computador anfitrión; `localhost` dentro del emulador apunta al propio emulador. El backend debe seguir activo. La carpeta Android ya está incluida: no hay que ejecutar antiguos scripts de preparación.

Estas instrucciones son para **debug y emulador**. Un teléfono físico necesita una dirección accesible desde ese teléfono y una configuración de red segura; este Compose publica solo en loopback. Un APK de producción requiere HTTPS, firma y configuración de despliegue. No uses la dirección de emulador como servidor de producción.

## 7. Crear cuentas y probar el flujo

Los pacientes se registran desde la pantalla de la aplicación. Administrador y profesional se crean desde terminal; no se permite escoger esos roles en el registro público.

Con la API Docker activa, desde la raíz:

```powershell
docker compose exec api node dist/database/create-privileged-account.js --role administrador --email admin@example.invalid
docker compose exec api node dist/database/create-privileged-account.js --role profesional --email profesional@example.invalid
```

Cada comando pide una contraseña de al menos 12 caracteres y su confirmación, sin mostrarla. Usa después esos correos y contraseñas en la pantalla normal de inicio de sesión. No hay una contraseña predeterminada.

Para probar:

1. Registra un paciente y sube un PDF o imagen ficticia con texto.
2. Solicita la extracción. El procesador automático debería tomar la solicitud; actualiza el estado después de esperar.
3. Entra como administrador y asigna ese paciente al profesional.
4. Entra como profesional, abre al paciente asignado, compara los datos con el documento original, corrige si hace falta y registra la revisión/observación.
5. Entra como paciente, actualiza el historial y consulta la copia revisada, la explicación y las preguntas sobre ese examen.
6. Comprueba también un documento sin texto y las restricciones del chat. Un indicador ficticio como Alfa no tiene un significado clínico que la IA deba inventar.

La interfaz actual es funcional, pero su rediseño y accesibilidad siguen pendientes. La comparación entre exámenes y otras mejoras de fases futuras no se consideran implementadas por incluir Docker.

## 8. Camino local, sin Docker

Instala Node 24 LTS, PostgreSQL 16, Ollama y Flutter. En pgAdmin crea una base de pruebas y utiliza un usuario autorizado para aplicar migraciones. El script de configuración no crea la base ni el usuario PostgreSQL.

Desde la raíz:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\configurar.ps1 -Modo Local
cd backend
npm ci
npm run build
npm run migrate
node --env-file=.env dist/database/check.js
node --env-file=.env dist/storage/check.js
ollama pull qwen3:4b-instruct
npm start
```

Deja esa terminal abierta. En otra terminal, desde la raíz:

```powershell
cd backend
npm run worker
```

En otra terminal, ejecuta Flutter como en web o Android. No ejecutes el antiguo comando manual `process-document --apply` mientras el procesador automático esté activo: ambos utilizan el mismo bloqueo exclusivo.

Si PostgreSQL está detenido en Windows, abre PowerShell como administrador, verifica el nombre del servicio y arráncalo:

```powershell
Get-Service *postgres*
net start postgresql-x64-16
```

Ese nombre corresponde a la instalación usada en desarrollo; si tu servicio tiene otro nombre, usa el que muestra `Get-Service`. Si Ollama no está activo, abre otra terminal y ejecuta `ollama serve`; si informa que el puerto ya está ocupado y `ollama list` funciona, ya estaba activo.

Para crear cuentas privilegiadas localmente:

```powershell
node --env-file=.env dist/database/create-privileged-account.js --role administrador --email admin@example.invalid
node --env-file=.env dist/database/create-privileged-account.js --role profesional --email profesional@example.invalid
```

## 9. Pruebas y cierre del entorno

Backend sin instalar Node en el anfitrión:

```powershell
docker build --target test -t vitalia-backend-test ./backend
```

Eso construye una etapa con dependencias de prueba y ejecuta Jest. La imagen normal de API no incluye herramientas de desarrollo. Si tienes Node instalado:

```powershell
cd backend
npm ci
npm test
```

Flutter:

```powershell
cd apps\vitalia
flutter analyze
flutter test
```

Para detener Docker desde la raíz:

```powershell
docker compose --profile web stop
```

Para iniciarlo otro día:

```powershell
docker compose up -d api worker
```

Si usabas GPU, incluye los dos archivos Compose como se indicó antes. Si usabas la web compilada, inicia también `docker compose --profile web up -d web`.

Los volúmenes conservan datos al detener los servicios. No ejecutes `docker compose down -v` si quieres conservar cuentas y trabajos: ese comando elimina los volúmenes de PostgreSQL y Ollama. Los documentos S3 no se borran con ese comando.

## 10. Si algo no funciona

- **No se pudo conectar con el servidor:** comprueba `docker compose ps -a` y `docker compose logs --tail 40 api`. En modo local verifica que `npm start` siga abierto. Web usa localhost:5173; emulador usa 10.0.2.2:3000.
- **API no inicia:** revisa que migrate terminó correctamente y que el bucket y las credenciales AWS estén vigentes. `docker compose run --rm migrate` repite migraciones de forma idempotente, sin borrar tablas.
- **Extracción pendiente:** revisa `docker compose logs --tail 40 worker` y `docker compose exec ollama ollama list`. El worker solo procesa modelos instalados y versiones de prompt compatibles.
- **Tiempo de IA excedido:** CPU puede tardar demasiado; comprueba recursos y el soporte GPU. No se acepta una respuesta parcial ni se amplía el tiempo indefinidamente.
- **Otro procesador activo:** detén el comando manual o el worker duplicado. No fuerces cambios de estado en la base.
- **Credenciales temporales caducadas:** renueva los datos del `.env` local y recrea API y worker con `docker compose up -d --force-recreate api worker`.
- **Puerto ocupado:** detén la ejecución anterior que usa 3000 o 5173. No cambies el puerto web al azar, porque el backend restringe el origen.
- **Cambiaste contraseña de la base en .env:** modificar el archivo no cambia la contraseña de un volumen PostgreSQL existente. Usa la configuración original o administra el cambio desde PostgreSQL; no borres volúmenes para resolverlo sin respaldar los datos.

## 11. Llevar esta rama al repositorio oficial

Esta rama limpia se descarga del repositorio de pruebas: selecciona `distribucion/equipo-docker` → Code → Download ZIP. No incluye archivos `.env` reales, node_modules, build ni documentos de avance.

En GitHub Desktop abre el repositorio oficial, crea o selecciona `develop` y copia el **contenido** del ZIP extraído a la raíz de esa rama. No copies una carpeta `.git` de otro repositorio. Antes de confirmar, revisa los archivos seleccionados: no agregues tu configuración local, credenciales, dependencias descargadas ni resultados de compilación. El ZIP de GitHub no incluye `.git` ni los secretos que generaste en tu equipo.

Después realiza el commit y Push origin desde `develop`. Tus compañeros podrán seleccionar esa rama y seguir esta guía. Los recursos de AWS, las cuentas locales y la configuración privada se preparan por separado en cada equipo.

## Estado de comprobación

La compilación TypeScript, las pruebas automatizadas backend y el análisis de referencias de la rama limpia se verifican antes de entregar la rama. Docker, PowerShell y Flutter/Android deben comprobarse en un equipo con esas herramientas: no se declara validado su arranque real solo por escribir los archivos. Esta es una distribución de desarrollo para pruebas del equipo, no un despliegue médico de producción.
