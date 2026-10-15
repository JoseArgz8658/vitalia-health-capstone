# Vitalia Health: instalación y pruebas en Windows

Esta guía está pensada para los computadores Windows del equipo. Todos los comandos se ejecutan en PowerShell. Conservamos Flutter para web y Android, backend, migraciones, pruebas y documentos de avance. Los cambios por fase están en `docs/Evidencias_Proyect/docs/avance` y `docs/Evidencias_Proyect/docs/cambios-codigo`.

Trabajamos con documentos ficticios. La extracción queda pendiente de revisión profesional y las respuestas educativas del asistente no constituyen diagnóstico ni tratamiento.

## 1. Elegir cómo ejecutar el proyecto

- **Con Docker:** Docker Desktop prepara PostgreSQL, API, procesador y Ollama. Flutter y Android Studio se instalan en Windows.
- **Sin Docker:** instalamos PostgreSQL, Node.js y Ollama en Windows, y arrancamos API y procesador en terminales separadas.
- **AWS S3:** usamos el bucket de pruebas compartido del equipo en ambos caminos. Cada integrante utiliza su propio acceso autorizado.

No ejecutes los dos caminos simultáneamente en los mismos puertos. Docker crea una base independiente de la que ya tienes instalada en Windows. Descargar GitHub no copia los datos de José.

## 2. Herramientas

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


Usamos Flutter 3.44.6, Dart 3.12.2 y Node 24 en el equipo de desarrollo. Las versiones de imágenes están fijadas en Dockerfile y Compose. Una primera instalación requiere Internet. Es recomendable contar con 16 GB de RAM y espacio para Docker, el modelo y el emulador. El rendimiento de IA depende del computador y sigue sujeto a evaluación.

## 3. Descargar la rama

En el repositorio [Vitalia Health](https://github.com/JoseArgz8658/vitalia-health-capstone), selecciona la rama `develop`. En GitHub Desktop pulsa Fetch origin y Pull origin. Si prefieres descargar sin Git, selecciona `develop` en GitHub y utiliza Code > Download ZIP.

Para una descarga nueva desde PowerShell:

```powershell
git clone --branch develop --single-branch https://github.com/JoseArgz8658/vitalia-health-capstone.git
cd vitalia-health-capstone
```

La raíz es la carpeta con `README.md`, `compose.yaml`, `backend` y `apps`. Si descargaste ZIP, entra a la carpeta extraída. Si el repositorio es privado, necesitas acceso autorizado. Todos los comandos de instalación parten de esta raíz, salvo cuando se indica otra carpeta.

## 4. Docker Desktop y WSL 2 en Windows

Instala Docker Desktop y utiliza el motor WSL 2 con contenedores Linux. Windows sigue siendo el sistema del equipo. No hace falta trabajar desde una terminal de Ubuntu.

Si WSL no está preparado, abre PowerShell **como administrador**:

```powershell
wsl --install
wsl --update
```

Reinicia si Windows lo solicita. Abre Docker Desktop y espera a que arranque el motor.

### Si Docker no arranca por virtualización o componentes de Windows

En el equipo de José, habilitar estos componentes y reiniciar resolvió el problema. Son pasos de recuperación para ese tipo de fallo, no una solución universal a cualquier error de Docker.

Comprueba en Administrador de tareas > Rendimiento > CPU que la virtualización esté habilitada. Si está deshabilitada, debes habilitarla desde BIOS/UEFI siguiendo las instrucciones del fabricante.

En PowerShell **como administrador**:

```powershell
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
bcdedit /set hypervisorlaunchtype auto
wsl --update
```

Reinicia el computador. Abre otra vez Docker Desktop. Los comandos DISM con `/norestart` no reinician por sí solos. En un equipo institucional, estos cambios pueden requerir autorización del administrador.

### Comprobar antes de continuar

En PowerShell normal:

```powershell
docker --version
docker compose version
docker compose version --short
docker info --format '{{.OSType}}'
wsl --status
```

Esperamos una versión de Compose, `linux` como tipo de contenedores y WSL 2. Si Compose no muestra versión, ejecuta `docker compose --help` y revisa Docker Desktop antes de continuar. No se considera validado solo porque el comando no imprimió un error.

Referencias: [instalación Docker en Windows](https://docs.docker.com/desktop/setup/install/windows-install/), [problemas de virtualización](https://docs.docker.com/desktop/troubleshoot-and-support/troubleshoot/topics/), [componentes WSL](https://learn.microsoft.com/es-es/windows/wsl/install-manual).

## 5. Acceso al bucket S3 del equipo

### Nota del acceso compartido — José Aránguiz

Les invité al acceso de AWS para trabajar con el proyecto. Juan Jiménez ya entró al portal; Diego Palma y Mauricio Reyes tenían pendiente ese ingreso. Además, ya preparé los tres usuarios IAM individuales y sus pares de claves para ejecutar el backend. Les entregaré a cada uno únicamente sus propias credenciales por interno. La entrega y la comprobación desde sus computadores siguen pendientes al 12 de octubre de 2026. **(José Aránguiz)**

No necesitan crear otro bucket ni nuevas claves para seguir esta instalación. Tampoco necesitan iniciar sesión en la consola AWS para ejecutar el backend con el par de claves que les proporcionaré. El acceso al portal y las credenciales del backend son distintos.

### Paso 1. Tener los datos del bucket

| Dato solicitado por el script | Qué debes introducir |
| --- | --- |
| Región AWS | `us-east-2` (Este de EE. UU., Ohio) |
| Nombre del bucket | `bucket-vitalia-health-0-949847740123-us-east-2-an` |
| AWS Access Key ID | La clave de acceso de tu usuario, que te entregaré por interno. (José Aránguiz) |
| AWS Secret Access Key | La clave secreta correspondiente al mismo usuario, que te entregaré por interno. (José Aránguiz) |
| AWS Session Token | **Dejar vacío y pulsar Enter** para los accesos IAM permanentes preparados para esta entrega. |

Copia el nombre del bucket exactamente. No añadas `arn:aws:s3:::`, `s3://`, una URL ni carpetas. El nombre contiene `us-east-2`, sin una «e» adicional.

### Paso 2. Identificar tus credenciales

| Integrante | Usuario IAM del backend | Estado al 12 de octubre de 2026 |
| --- | --- | --- |
| Juan Jiménez | `vitalia-dev-juan` | Usuario y claves preparados. Entrega y prueba pendientes. |
| Diego Palma | `vitalia-dev-diego` | Usuario y claves preparados. Entrega y prueba pendientes. |
| Mauricio Reyes | `vitalia-dev-mauricio` | Usuario y claves preparados. Entrega y prueba pendientes. |

Preparé estos usuarios con la política `VitaliaS3DevPolicy`. Comparten el mismo bucket y el prefijo `patients/*`, pero tienen credenciales individuales. No les enviaré la clave de `vitalia-backend-dev`, que corresponde al backend que configuré inicialmente. **(José Aránguiz)**

1. Solicítame por interno el par de claves correspondiente a tu usuario.
2. Guarda ambos valores de forma privada. No los pegues en GitHub, en el chat grupal ni en capturas.
3. Usa ese par de claves en el script del paso 4. No combines una clave de acceso con la secreta de otro usuario.
4. Deja Session Token vacío para estos accesos permanentes. Si en el futuro cambiamos a credenciales temporales, revisaremos las instrucciones.
5. Si falta alguno de los dos valores, avísame. No crees otra clave ni uses la de un compañero. **(José Aránguiz)**

### Paso 3. Entender el alcance del acceso compartido

Todos estos usuarios pueden subir, consultar y eliminar objetos dentro de `patients/*`. No hemos separado los archivos por integrante. Coordinen antes de borrar un documento que esté utilizando otro compañero.

El acceso al bucket no copia PostgreSQL ni hace aparecer los exámenes en el historial. Para utilizar los registros actuales, también necesitan restaurar el respaldo de datos de prueba que les proporcionaré según la sección 11. La entrega y restauración de ese respaldo todavía están pendientes. **(José Aránguiz)**

IAM Identity Center no forma parte de este procedimiento. No habilité acceso de consola para estos usuarios del backend y no les concedí permisos para administrar usuarios o claves IAM. La prueba del paso 5 confirmará si las credenciales funcionan en la aplicación.

Referencia: [gestión de claves IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html).

### Paso 4. Configurar el entorno elegido

Desde la raíz del proyecto, en PowerShell:

**Para Docker:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\configurar.ps1 -Modo Docker
```

**Para ejecución sin Docker:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\configurar.ps1 -Modo Local
```

Ejecuta solo el que corresponda a tu instalación. El script pregunta región, nombre del bucket y tus credenciales. Para credenciales temporales introduce también el Session Token. Para claves permanentes deja ese token vacío y pulsa Enter.

Docker crea `.env` en la raíz. La ejecución local crea `backend/.env`. Si el archivo ya existe, el script no lo reemplaza; revisa el archivo del entorno correcto en tu editor. No publiques su contenido ni envíes capturas de las claves.

### Paso 5. Comprobar S3

Primero completa el arranque y compilación del camino elegido en las secciones 6 o 7. Después comprueba:

**Con Docker, desde la raíz y con la imagen del backend construida:**

```powershell
docker compose run --rm --no-deps api node dist/storage/check.js
$LASTEXITCODE
```

**Sin Docker, desde la carpeta backend después de npm run build:**

```powershell
node --env-file=.env dist/storage/check.js
$LASTEXITCODE
```

Esperamos el mensaje de conexión a S3 correcta, bloqueo público y ACL deshabilitadas, seguido de código `0`. Esta comprobación no sustituye la prueba posterior de subir y consultar un documento.

Si aparece `NoSuchBucket` o `NotFound`, revisa el nombre del bucket en el archivo correcto: raíz para Docker y backend para local. Si aparece `AccessDenied`, revisaremos permisos; si las credenciales temporales caducaron, renueva la sesión.

El backend requiere ListBucket y las comprobaciones de seguridad del bucket, además de PutObject, GetObject y DeleteObject sobre `patients/*`. El bucket se mantiene privado y con ACL deshabilitadas. Coordinaremos cualquier cambio de permisos y pruebas de borrado. (José Aránguiz)

[Guía de credenciales AWS](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html).

## 6. Ejecutar con Docker

Desde la raíz del proyecto:

```powershell
Test-Path .env
Test-Path backend\.env
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\configurar.ps1 -Modo Docker
```

El script crea `.env` en la raíz y genera la contraseña del PostgreSQL Docker. No modifica `backend/.env`. Si el archivo de destino ya existe, se detiene para no sobrescribirlo. Usa región y bucket compartidos y tus credenciales autorizadas.

Antes de arrancar:

```powershell
docker compose config --quiet
docker compose config --services
```

No compartas la salida de `docker compose config` sin `--quiet`: puede mostrar secretos.

Arranca la base y descarga el modelo:

```powershell
docker compose up -d postgres ollama
docker compose exec ollama ollama pull qwen3:4b-instruct
docker compose exec ollama ollama list
```

El modelo de Docker se guarda en su propio volumen. No utiliza automáticamente el modelo instalado en Windows.

Detén con Ctrl+C las terminales anteriores de API, worker o Flutter si van a usar los mismos puertos. Después:

```powershell
docker compose up -d --build api worker
docker compose ps -a
docker compose logs --tail 40 migrate api worker
```

`migrate` debe finalizar con código 0. La API debe iniciar y el worker debe indicar que espera trabajos. El worker se mantiene activo, aunque no haya solicitudes. PostgreSQL y Ollama no publican puertos en este Compose. La API utiliza `127.0.0.1:3000`.

### GPU NVIDIA opcional

Solo para equipos con GPU y controladores compatibles con Docker y WSL 2:

```powershell
docker compose -f compose.yaml -f compose.gpu.yaml up -d postgres ollama
docker compose exec ollama ollama pull qwen3:4b-instruct
docker compose -f compose.yaml -f compose.gpu.yaml up -d --build api worker
```

Usa ambos archivos también en posteriores arranques si elegiste GPU. Sin GPU, utiliza los comandos normales. [GPU en Docker Desktop Windows](https://docs.docker.com/desktop/features/gpu/).

## 7. Ejecutar sin Docker

Instala Node 24, PostgreSQL 16, Ollama y Flutter. Crea una base de pruebas y un usuario autorizado en PostgreSQL. El script no crea la base ni el usuario.

Si ya tienes `backend/.env` funcionando, consérvalo y omite la generación. Para una instalación nueva, desde la raíz:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\configurar.ps1 -Modo Local
```

`backend/.env.example` sirve como referencia sin secretos. Para iniciar la API:

```powershell
cd backend
npm ci
npm run build
npm run migrate
node --env-file=.env dist/database/check.js
node --env-file=.env dist/storage/check.js
ollama pull qwen3:4b-instruct
npm start
```

En otra terminal desde la raíz:

```powershell
cd backend
npm run worker
```

No ejecutes el procesador manual mientras el worker esté activo. Para PostgreSQL detenido, en PowerShell administrador:

```powershell
Get-Service *postgres*
net start postgresql-x64-16
```

Verifica el nombre real del servicio. Para Ollama detenido, abre otra terminal con `ollama serve`. Si el puerto ya está ocupado y `ollama list` funciona, ya existe un servidor.

## 8. Abrir la web

Con API y worker activos, desde la raíz en otra terminal:

```powershell
cd apps\vitalia
flutter pub get
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

Abre `http://localhost:5173`. Mantén la terminal abierta. Para web compilada con Docker, desde la raíz:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\crear-web.ps1
docker compose --profile web up -d web
```

Elige una opción. Ambas usan el puerto 5173 y no deben arrancar simultáneamente.

## 9. Android en Windows

En Android Studio abre Device Manager y crea un emulador Pixel 3a o Pixel 6. Para la primera prueba, usa Android 15 / API 35 con arquitectura compatible con tu PC, normalmente x86_64 en Intel/AMD. El SDK definitivo depende de `flutter doctor` y del proyecto. Prueba más tamaños y versiones antes de afirmar compatibilidad completa.

Arranca el emulador y ejecuta, desde `apps\vitalia`:

```powershell
flutter doctor --android-licenses
flutter doctor
flutter pub get
flutter devices
flutter run -d emulator-5554 --dart-define=VITALIA_API_URL=http://10.0.2.2:3000
```

Usa el identificador que devuelva `flutter devices` si es diferente. `10.0.2.2` conecta el emulador al anfitrión Windows. Esta guía corresponde a debug y emulador. Un teléfono físico o APK productivo necesita dirección accesible, HTTPS, firma y configuración específica.

## 10. Cuentas y recorrido de prueba

Para una base nueva, el paciente se registra en la app. Administrador y profesional se crean desde terminal con contraseña propia, sin selector público de roles.

Con Docker, desde la raíz:

```powershell
docker compose exec api node dist/database/create-privileged-account.js --role administrador --email admin@example.invalid
docker compose exec api node dist/database/create-privileged-account.js --role profesional --email profesional@example.invalid
```

Sin Docker, desde `backend`:

```powershell
node --env-file=.env dist/database/create-privileged-account.js --role administrador --email admin@example.invalid
node --env-file=.env dist/database/create-privileged-account.js --role profesional --email profesional@example.invalid
```

Los comandos piden contraseña y confirmación. Para probar:
1. El paciente sube un documento ficticio con texto y solicita extracción.
2. El worker procesa y guarda el resultado pendiente de revisión.
3. El administrador asigna paciente al profesional en el flujo actual de pruebas.
4. El profesional coteja el original, corrige si corresponde y aprueba una copia revisada.
5. El paciente consulta resultados, explicación y chat del examen.
6. Comprueba también una imagen sin texto y una solicitud de tratamiento que el asistente debe rechazar.

La elección del médico por el paciente, perfiles completos y atención multiclínica siguen pendientes de implementación. No se consideran disponibles por tener un diagrama propuesto.

## 11. Compartir los datos actuales de PostgreSQL — José Aránguiz

Preparé un respaldo de mi base de Windows `vitalia_dev` desde pgAdmin 4 para pasárselo por interno al grupo. Restauré una copia de comprobación, comparé los conteos y confirmé lectura con `vitalia_app`: 10 documentos y 4 revisiones. La entrega y la restauración en los computadores de mis compañeros siguen pendientes. **(José Aránguiz)**

No deben conectarse a mi servidor. Cada uno tendrá su propia copia. Los cambios de PostgreSQL no se sincronizan entre computadores. Los PDF e imágenes siguen en el bucket compartido de S3 y no están dentro del .backup.

### Paso 1. Recibir el respaldo

1. Solicítame el archivo .backup por interno. No lo descargues de GitHub ni publiques su contenido. (José Aránguiz)
2. Guárdalo fuera del repositorio, por ejemplo en una carpeta `VitaliaBackups` de tus Documentos.
3. El respaldo contiene cuentas, hashes de contraseña, sesiones y conversaciones existentes. Lo revisaremos antes de compartirlo y usaremos únicamente datos adecuados para las pruebas del equipo.
4. Las contraseñas del servidor PostgreSQL y las claves AWS se configuran por separado. El respaldo de una base no crea los usuarios del servidor PostgreSQL.

### Paso 2. Crear una base local de destino en Windows

Este procedimiento es para PostgreSQL instalado en Windows, no para el volumen Docker. Si elegiste exclusivamente Docker, avísame antes de restaurar: el contenedor no aparece automáticamente en pgAdmin y no debes asumir que localhost:5432 apunta a él. (José Aránguiz)

1. Instala PostgreSQL 16 y abre pgAdmin 4.
2. Conéctate a tu servidor local con la cuenta administradora.
3. Haz clic derecho en **Databases > Create > Database**.
4. Nombre: `vitalia_equipo`. Owner: la cuenta administradora `postgres`.
5. Guarda. La base debe ser nueva y vacía. Si el nombre ya existe, detente y acuerda otro destino; no borres datos existentes.

No uses vitalia_app como cuenta de administración ni de migraciones.

### Paso 3. Preparar el esquema vacío

El respaldo incluye CREATE SCHEMA public. Una base nueva normalmente ya contiene public y esto provocó el primer error que encontré. Para evitarlo, abre **Query Tool sobre vitalia_equipo**, conectado como postgres, y ejecuta:

```sql
BEGIN;
DO $$
BEGIN
  IF current_database() <> 'vitalia_equipo' THEN
    RAISE EXCEPTION 'Base incorrecta: operación cancelada';
  END IF;
  EXECUTE 'DROP SCHEMA public';
END
$$;
COMMIT;
```

Solo se retira el esquema vacío de esta base nueva. Sin CASCADE, el comando falla si existen objetos dentro. No ejecutes esto en tu base de trabajo ni en vitalia_dev. Si falla, ejecuta ROLLBACK y revisa el destino; no añadas CASCADE para forzarlo.

### Paso 4. Restaurar mediante pgAdmin

1. Clic derecho en **vitalia_equipo > Restore**.
2. General: formato **Custom**, selecciona el archivo recibido. Number of jobs y Role name vacíos.
3. Data options: activa **Pre-data, Data y Post-data**. Deja Only data y Only schema desactivados.
4. Do not save: activa **Owner, Privileges y Tablespace**. Deja los demás desactivados.
5. Query options: deja **Clean before restore** y **CREATE DATABASE** desactivados.
6. Si aparecen, activa **Single transaction** y **Exit on error**. Deja Disable triggers desactivado.
7. Comprueba el nombre de destino y pulsa Restore.
8. Revisa Ver procesos: debe terminar correctamente, sin errores.

Mi restauración comprobada terminó Successfully completed. El comando de ese intento no incluía single-transaction ni exit-on-error; no afirmo haber probado esas opciones. Si tu restauración falla, conserva el registro y avísame antes de repetirla sobre una base parcialmente cargada. (José Aránguiz)

### Paso 5. Preparar el usuario de aplicación

Los objetos restaurados como postgres quedan bajo su propiedad. Omitimos privilegios para no copiar permisos de otro computador.

En **Login/Group Roles > Create > Login/Group Role** de tu servidor:
1. Crea `vitalia_app` si no existe.
2. Define una contraseña propia y permite iniciar sesión.
3. No habilites Superuser, Create databases ni Create roles.
4. Si ya existe, no cambies su contraseña o atributos sin comprobar qué aplicaciones lo utilizan.

Después, desde Query Tool de **vitalia_equipo**, conectado como postgres:

```sql
BEGIN;
DO $$
BEGIN
  IF current_database() <> 'vitalia_equipo' THEN
    RAISE EXCEPTION 'Base incorrecta: operación cancelada';
  END IF;
END
$$;
GRANT CONNECT ON DATABASE vitalia_equipo TO vitalia_app;
GRANT USAGE ON SCHEMA public TO vitalia_app;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO vitalia_app;
GRANT INSERT, UPDATE, DELETE ON TABLE
  public.vitalia_accounts,
  public.vitalia_sessions,
  public.vitalia_documents,
  public.vitalia_document_cleanup,
  public.vitalia_document_processing,
  public.vitalia_patient_assignments,
  public.vitalia_exam_explanations,
  public.vitalia_exam_assistant_threads,
  public.vitalia_exam_assistant_turns
TO vitalia_app;
GRANT INSERT ON TABLE
  public.vitalia_professional_reviews,
  public.vitalia_document_audit,
  public.vitalia_assignment_audit,
  public.vitalia_professional_access_audit,
  public.vitalia_explanation_audit,
  public.vitalia_exam_assistant_audit
TO vitalia_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vitalia_app;
COMMIT;
```

Estos GRANT no conceden modificación de roles o migraciones, ni actualización o eliminación directa de revisiones. No revocan permisos anteriores de un rol que ya existía. Si falla algún comando, ejecuta ROLLBACK y revisa el mensaje.

Comprobé estas concesiones en mi copia y la conexión de lectura como vitalia_app; el recorrido completo de escritura de la aplicación contra esta copia sigue pendiente. (José Aránguiz)

### Paso 6. Configurar y comprobar el backend local

En tu `backend/.env`, configura:
- PGHOST: `127.0.0.1`.
- PGPORT: el de tu PostgreSQL, normalmente `5432`.
- PGDATABASE: `vitalia_equipo`.
- PGUSER: `vitalia_app`.
- PGPASSWORD: la contraseña que definiste en tu computador.
- AWS: bucket compartido y tus propias claves.

Desde backend, compila y comprueba las conexiones como en la sección 7. El respaldo completo ya contiene el esquema y el registro de migraciones: no necesitas ejecutar migraciones como vitalia_app para comenzar. Para futuras migraciones se requiere la cuenta administradora y una configuración separada.

Los GRANT anteriores se aplican después de restaurar. No están dentro del respaldo que comparto, porque lo generé sin privilegios. (José Aránguiz)

### Paso 7. Consultar los documentos compartidos

Inicia API y worker solo cuando hayas comprobado configuración y permisos. Verifica el historial, la copia revisada y el acceso al original S3. Los correos y contraseñas de cuentas de prueba de la aplicación se coordinan por privado; no son las credenciales PostgreSQL.

Una copia de la base conserva los mismos identificadores y referencias S3. **Borrar un documento puede eliminar el archivo compartido que utiliza el resto del grupo.** Coordina las pruebas de borrado y no ejecutes eliminación o recuperación automática de archivos compartidos sin revisar su alcance. Tampoco proceses el mismo trabajo pendiente desde varias copias sin coordinación.

### Cómo generé el respaldo original

En pgAdmin hice clic derecho en vitalia_dev > Backup, formato Custom, con Pre-data, Data y Post-data y todos los objetos de public, incluidas sus dos secuencias. Dejé Only data y Only schema desactivados y Blobs activado. Omití Owner, Privileges y Tablespaces. Lo guardé fuera de GitHub. El detalle de restauración y comparación está en [CAM-079](docs/Evidencias_Proyect/docs/cambios-codigo/CAM-079-respaldo-restauracion-pgadmin.md). (José Aránguiz)

## 12. Pruebas, parada y problemas comunes

Backend local, desde `backend`:

```powershell
npm ci
npm test
```

Backend con Docker, desde la raíz:

```powershell
docker build --target test -t vitalia-backend-test ./backend
```

Flutter, desde `apps\vitalia`:

```powershell
flutter analyze
flutter test
```

Para detener Docker sin eliminar datos:

```powershell
docker compose --profile web stop
```

Para volver a iniciar:

```powershell
docker compose up -d api worker
```

Si usabas GPU, incluye ambos Compose. Si usabas web compilada, inicia también `docker compose --profile web up -d web`. **No uses `docker compose down -v` para conservar datos:** elimina volúmenes PostgreSQL y Ollama.

- Servidor no disponible: revisa API, puerto 3000 y origen web localhost:5173.
- Extracción pendiente: revisa logs del worker y modelo instalado. Una subida no inicia procesamiento sin la solicitud actual.
- Credenciales S3 vencidas: renueva tu sesión, actualiza tu configuración local y recrea API/worker. Nunca envíes los valores al chat.
- Puerto ocupado: detén el proceso anterior. No arranques ambos caminos simultáneamente.
- Cambiar PGPASSWORD en .env no cambia la contraseña de un volumen PostgreSQL existente.
- Trabajo fallido: actualizar solo consulta. El worker no repite trabajos indefinidamente ni modifica revisiones aprobadas.
- Tras un reinicio del worker, un trabajo interrumpido puede quedar fallido. Utiliza una copia ficticia nueva para otra prueba.

## 13. Evidencias y actualización del proyecto

Conservamos los CAM y avances por fase como registros técnicos. Los datos actuales y el modelo propuesto se distinguen en `docs/Evidencias_Proyect/docs/base-datos`. Las mejoras pendientes están en `docs/Evidencias_Proyect/docs/pendientes`.

Para actualizar tu copia desde GitHub Desktop, selecciona `develop`, pulsa Fetch origin y después Pull origin. Desde la raíz también puedes ejecutar:

```powershell
git switch develop
git pull --ff-only
```

Conserva la configuración local. No subas .env, respaldos, node_modules ni compilaciones. El código compartido se obtiene del repositorio oficial `https://github.com/JoseArgz8658/vitalia-health-capstone.git`, rama `develop`.

### Estado de comprobación al 12 de octubre de 2026 — José Aránguiz

Confirmé Compose 5.5.1, migraciones 001–011, conexión PostgreSQL y S3, el flujo paciente–extracción–revisión–consulta con Docker y sin Docker, y conservación de cuentas y revisión tras detener y volver a iniciar los contenedores.

La primera extracción Docker agotó el tiempo. Con compose.gpu.yaml y RTX 3050 de 4 GB, Ollama utilizó CPU/GPU y el nuevo intento terminó pendiente de revisión. No es una garantía de rendimiento para otros equipos.

Con Jest 30.5.2, npm test aprobó 423 pruebas de 40 suites. npm audit --omit=dev reportó cero vulnerabilidades; la auditoría completa mantiene 19 avisos moderados en la cadena de desarrollo de sprintf-js. No aplicar audit fix --force: propone una bajada incompatible de Jest. Detalle y seguimiento: [CAM-078](docs/Evidencias_Proyect/docs/cambios-codigo/CAM-078-jest-validacion-windows.md).

Las fechas de la copia revisada requieren DD-MM-AAAA. Si se corrige información o quedan campos ausentes, registrar observación y confirmar el cotejo con el original. Las incidencias originales permanecen como evidencia.

Si Windows bloquea impellerc.exe, revisar la directiva de control de aplicaciones antes de cambiar seguridad. Desactivar protecciones no es requisito general del manual.

Android, web compilada con Nginx, restauración de respaldos, instalación completa en otro equipo y accesos AWS del resto del equipo quedan por comprobar. Los registros de esta sesión están en CAM-078.

### Posibles problemas durante la instalación

Durante la instalación y las pruebas de Vitalia Health pueden aparecer algunos problemas con la configuración o los servicios. Dejo algunas situaciones que encontré y las comprobaciones que me sirvieron para resolverlas.

**1. Docker muestra errores con el archivo `.env`**

Si Docker presenta errores al validar la configuración, recomiendo revisar primero que las variables del archivo `.env` estén bien escritas.

En mi caso, tuve que corregir algunas líneas relacionadas con las credenciales de AWS porque tenían problemas de formato.

Para comprobar la configuración utilicé:

```powershell
docker compose config --quiet
```

Después de corregirlas, el comando terminó sin errores y pude continuar con la instalación. Esto comprueba el formato de la configuración, pero no garantiza que las credenciales sean correctas.

**2. Los contenedores están encendidos, pero no sabemos si funcionan correctamente**

Aunque Docker muestre los servicios iniciados, conviene comprobar que estén respondiendo.

Para revisar su estado:

```powershell
docker compose ps -a
```

Si alguno presenta problemas, podemos consultar sus registros:

```powershell
docker compose logs --tail 40 api worker postgres ollama
```

También podemos comprobar que la API responda:

```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/health"
```

En mi caso, la API respondió con `status: ok`. Después comprobé por separado PostgreSQL, Ollama y el almacenamiento S3 para asegurarme de que los servicios necesarios estuvieran funcionando.

**3. Problemas con la conexión a AWS S3**

Si aparecen errores al trabajar con documentos, podemos comprobar la conexión del backend con el bucket:

```powershell
docker compose exec api node dist/storage/check.js
```

En mi caso, esta prueba confirmó que podía conectarme al bucket y que tenía habilitadas las protecciones esperadas.

Si aparece un error, conviene revisar la región, el nombre del bucket y las credenciales configuradas. No es necesario compartir las claves para pedir ayuda; basta con enviar el mensaje de error, cuidando que no incluya información privada.

**4. El documento se sube, pero Ollama no lo procesa**

Primero podemos revisar que el Worker esté funcionando y que Ollama tenga el modelo descargado:

```powershell
docker compose logs --tail 40 worker
docker compose exec ollama ollama list
```

También hay que recordar que subir un documento no inicia automáticamente su procesamiento. La aplicación debe solicitar el análisis.

En mi caso, probé con un PDF ficticio y confirmé que pasó por los estados `queued`, `processing` y `requires_review`.

El último estado no significa necesariamente que el servicio haya fallado. Puede indicar que el análisis terminó, pero que los datos necesitan revisión antes de aprobarse.

**5. Ollama extrae algunos datos incorrectamente**

En mi caso, hice una prueba con un hemograma ficticio. Ollama reconoció correctamente los valores de hemoglobina, leucocitos y plaquetas, pero no logró extraer la fecha y agregó rangos de referencia que no aparecían en el PDF.

El procesamiento terminó en `requires_review`, así que revisé el resultado almacenado en PostgreSQL para identificar qué había ocurrido.

Este comportamiento ya está identificado por el equipo y se está trabajando en mejorarlo. Si aparece otro caso parecido, conviene guardar el resultado y anotar qué información no coincide con el documento original.

**Nota:** Si algo no funciona a la primera, recomiendo revisar el mensaje de error antes de reinstalar o borrar cualquier cosa. A veces basta con corregir una variable o esperar a que un servicio termine de iniciar. Evitemos eliminar los volúmenes de Docker para solucionar estos problemas, porque podríamos perder los datos guardados en PostgreSQL.
