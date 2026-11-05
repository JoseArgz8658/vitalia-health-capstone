# Fase 7.1 — Base de perfiles y ubicación

Preparé la migración 012_profiles_locations y su comprobación para PostgreSQL. La continuación CAM-083 añade consulta/edición del perfil propio y su pantalla Flutter. Conservé la autenticación y los datos de cuentas y exámenes existentes. (José Aránguiz)

## Tablas nuevas

| Tabla | Finalidad | Relación principal |
|---|---|---|
| vitalia_regions | Catálogo de regiones | PK code |
| vitalia_provinces | Provincias de una región | region_code → regions.code |
| vitalia_communes | Comunas de una provincia | province_code → provinces.code |
| vitalia_people | Datos personales sin repetir credenciales | account_id único → accounts.id; comuna preferida opcional |
| vitalia_person_identifiers | Identificadores por persona, país y tipo | person_id → people.id; dos restricciones UNIQUE |
| vitalia_patient_profiles | Perfil paciente de una persona | person_id como PK y FK |
| vitalia_professional_profiles | Perfil profesional separado de sus permisos | person_id como PK y FK |
| vitalia_patient_measurements | Peso y altura con fecha y procedencia | patient_person_id → patient_profiles; recorded_by → accounts |

Son ocho tablas y nueve claves foráneas nuevas. Sobre el esquema anterior de 17 tablas, la migración completa deja 25. El diagrama ampliado anterior sigue siendo una propuesta para el resto de entidades, no prueba de que todas estén implementadas. (José Aránguiz)

## Reglas de este incremento

- Una cuenta puede seguir sin persona/perfil; una persona puede tener perfil paciente y profesional sin cambiar role_code ni obtener permisos nuevos.
- Primer nombre y primer apellido obligatorios al crear persona. Segundo nombre, segundo apellido, teléfono, nacimiento y comuna son opcionales en esta estructura. La fecha de nacimiento será exigida por el futuro flujo de perfil completo del paciente.
- No guardo edad fija. Rechazo fechas de nacimiento futuras o infinitas. Las medidas requieren fecha no futura, al menos un dato positivo y finito, fuente y autor.
- El RUT no sustituye el UUID. La combinación país/tipo/valor es única, y una persona tiene un identificador por país/tipo. CAM-083 normaliza puntos/guion/K y valida módulo 11 antes de guardarlo por API. No acredita identidad. Un RUT ya registrado no puede vaciarse mediante el formulario; si está verificado, no se permite cambiarlo.
- Los identificadores nacen como not_verified y los profesionales como pending. La creación de una fila no verifica identidad o habilitación profesional. Los futuros servicios controlarán quién puede cambiar esos estados.
- La migración 012 deja los catálogos territoriales vacíos. CAM-086 incorpora una carga explícita del catálogo SUBDERE-CUT-2018-v04; no se ejecuta automáticamente ni inventa territorios.
- El servicio actualiza updated_at al editar y utiliza su revisión para rechazar un guardado obsoleto; no hay trigger automático. Las FK conservan el borrado restringido por defecto.
- Las FK no implementan aislamiento multiclínica ni acceso profesional por sí mismas. La API de perfiles solo permite editar datos propios, obteniendo la identidad de la sesión. Tampoco envío perfiles o medidas al asistente.

Conservo para los bloques siguientes las clínicas y sucursales, invitaciones institucionales de jefes clínicos, gestión de médicos, atención por examen y extracción/chat preliminar. El registro público actual continúa funcionando. (José Aránguiz)

## Probar en Windows sin aplicar cambios todavía

Abre PowerShell de VS Code en la raíz del repositorio de prueba. Conserva cambios locales antes de cambiar de rama:

```powershell
git fetch origin
git switch fase-7/01-perfiles-ubicacion
cd backend
npm ci
npm test
$LASTEXITCODE
```

La compilación y Jest no aplican migraciones a tu servidor. La rama incluye la carpeta database en la etapa de pruebas Docker, conservando la corrección ya validada por el equipo. No pide instalar PGlite ni nuevas dependencias del proyecto.

## Aplicar después de revisar y respaldar

Estos pasos modifican la base indicada en backend/.env. Antes, comprueba su nombre, realiza un respaldo y confirma que las once migraciones anteriores están aplicadas. Usa una cuenta de migraciones con permisos DDL; no amplíes vitalia_app a superusuario. Si no identificas qué base utiliza el archivo, detente antes de ejecutar el comando de migración.

Desde backend, con PostgreSQL 16 activo:

```powershell
node --env-file=.env dist/database/check.js
$LASTEXITCODE
```

Solo si la comprobación anterior termina con 0 y ya decidiste aplicar el cambio en esa base:

```powershell
node --env-file=.env dist/database/migrate-profiles-locations.js
$LASTEXITCODE
```

Esperado: Migración de perfiles y ubicación aplicada. Repetir conserva las tablas y responde que ya estaba aplicada. Si falla, no borres ni edites migraciones anteriores ni elimines tablas para forzarla.

La comprobación posterior inserta únicamente datos sintéticos en una transacción y siempre intenta revertirlos:

```powershell
node --env-file=.env dist/database/verify-profiles-locations.js
$LASTEXITCODE
```

Esperado: Perfiles y ubicación: 33 comprobaciones correctas. Datos sintéticos revertidos. Código 0. Necesita permisos para crear y revertir esas filas; no usa S3 ni Ollama. No convierte al paciente en profesional por tener ambos perfiles.

## Docker

No arranques esta rama contra los volúmenes habituales sin revisar y respaldar: migrate-all descubre automáticamente el archivo 012 y Compose puede ejecutarlo al iniciar servicios. La prueba de imagen por sí sola no migra una base externa:

```powershell
docker build --target test -t vitalia-backend-test ./backend
$LASTEXITCODE
```

## Validación inicial en el entorno de comprobación

Comprobé SQL, idempotencia, huella modificada rechazada, requisito 011 y reversión ante un fallo DDL en PGlite (motor PostgreSQL WASM aislado). Verifiqué las 33 reglas con el mismo comprobador y que la cuenta antigua permaneciera intacta. PGlite se instaló fuera del proyecto solo para esta comprobación; no se incorpora a package.json. No equivale a PostgreSQL 16, Docker o prueba de permisos de vitalia_app. La comprobación posterior en Windows se registra a continuación. (José Aránguiz)

### Resultado posterior en PostgreSQL 16

Apliqué 012 en vitalia_dev como postgres y ejecuté las 33 comprobaciones con datos revertidos, código 0. Registré la evidencia y los permisos inicialmente ausentes de vitalia_app en CAM-082. (José Aránguiz)

## Habilitar Mi perfil en el entorno local

No repitas la migración si ya está aplicada. Actualiza esta rama y ejecuta npm test en backend, y flutter analyze/flutter test en apps/vitalia. El backend normal sigue usando vitalia_app.

Para habilitar el acceso de ese usuario a las nuevas tablas, abre en VS Code backend/database/permissions/profiles-app.sql y revisa todo su contenido. En pgAdmin, conectado como postgres a vitalia_dev, abre Query Tool, pega el archivo completo y ejecútalo. Es una concesión de permisos persistente; no es la comprobación con rollback. No ejecutes el archivo sobre otra base ni lo adaptes para Docker sin revisar roles y destino.

Después inicia API y Flutter como habitualmente. En Mis exámenes o Mis pacientes pulsa el icono de persona con ayuda Mi perfil. La pantalla abre en consulta, dividida en Datos personales, Contacto e Identificación. Pulsa Editar datos personales para habilitar los campos. Completa primer nombre y primer apellido; los demás campos son opcionales en este incremento. Guarda para volver a consulta, o pulsa Cancelar edición para descartar el borrador sin enviarlo. Vuelve al inicio y abre Mi perfil nuevamente: debe conservar los datos guardados. Prueba un RUT con dígito incorrecto y comprueba que no se guarda. Una cuenta distinta debe ver su propio perfil vacío. Si la sesión expira, debe volver a acceso. Comprueba que subir/consultar exámenes siga funcionando.

La edición de estos datos no modifica revisiones aprobadas ni la información usada por el asistente. La carga y selección territorial se incorpora posteriormente en CAM-086; la elección de profesional y las invitaciones clínicas siguen pendientes. (José Aránguiz)

## Medidas personales — CAM-085

Después de guardar los datos personales del paciente aparece el módulo Medidas personales. Primero revisa el script backend/database/permissions/profiles-app.sql actualizado: añade SELECT e INSERT por columnas sobre patient_measurements. Una vez comprobadas las pruebas del incremento, ejecútalo completo en pgAdmin como postgres sobre vitalia_dev, igual que en el incremento anterior. Las concesiones se pueden repetir; no hace falta volver a migrar 012. El script no modifica permisos sobre otra base y no debe adaptarse al contenedor sin revisar su destino.

Reinicia API y Flutter con la configuración local habitual. En Mi perfil consulta el módulo y pulsa Registrar medidas. Escribe peso en kg o altura en cm, o ambos; se admite coma decimal. La fecha inicial es el momento de abrir el formulario, y puedes elegir otro día anterior o actual. Al guardar queda un registro histórico nuevo. Al cancelar no se envían datos. La interfaz muestra hasta veinte registros recientes con su procedencia declarada por el paciente. No se permite editar ni borrar registros históricos en este bloque.

Si falla la conexión y no sabes si se guardó, puedes cancelar el formulario y actualizar medidas para consultar el servidor. Reintentar el mismo formulario sin cambiarlo conserva el identificador y no debe duplicar el registro. Comprueba persistencia al cerrar y reabrir el perfil, separación entre cuentas, rechazo de cero/negativos y cancelación sin guardado. Ningún dato de este módulo se envía al asistente. (José Aránguiz)

## Ubicación opcional — CAM-086

Añadí el catálogo de SUBDERE y selectores en Contacto del perfil. Antes de aplicarlo, actualiza la rama y ejecuta npm test, flutter analyze y flutter test. La comprobación de backend registrada es 499 pruebas en 44 suites. No vuelvas a ejecutar la migración 012. (José Aránguiz)

Una vez revisadas las pruebas, desde backend ejecuta el cargador con una cuenta administrativa de PostgreSQL local y PGDATABASE=vitalia_dev. El comando es:

```powershell
node --env-file=.env dist/database/load-territories.js
$LASTEXITCODE
```

No cambies permanentemente el usuario de la aplicación a postgres. Utiliza credenciales administrativas solo en la terminal de carga y restáuralas al terminar. El resultado esperado es Catálogo territorial cargado: 16 regiones, 56 provincias y 346 comunas, salida 0. Repetir debe informar que ya estaba cargado y coincide. El cargador no se ejecuta al iniciar la API, rechaza otra base y revierte ante datos territoriales distintos. (José Aránguiz)

Revisa y ejecuta el archivo completo backend/database/permissions/profiles-app.sql como postgres en Query Tool de vitalia_dev. Añade lectura de regiones/provincias/comunas a vitalia_app, sin escritura. Debe finalizar con COMMIT. Después reinicia la API habitual como vitalia_app y Flutter. (José Aránguiz)

En Mi perfil, consulta Contacto y pulsa Editar datos personales. Elige región, provincia y comuna y guarda. Al volver a entrar deben aparecer los nombres. Cambiar región limpia provincia/comuna; cambiar provincia limpia comuna. Si elegiste región, completa comuna o utiliza Quitar ubicación antes de guardar. Cancelar edición restaura lo guardado. Si no se puede cargar el catálogo se conserva el código anterior y puedes editar los otros campos. No se envía ubicación a la IA ni se utiliza como domicilio verificado. (José Aránguiz)

La versión fuente es CUT 2018 de SUBDERE, con procedencia y huellas en backend/database/catalogs/README.md. Mantengo pendientes pruebas directas Windows/PostgreSQL 16, auditoría de cambios y rectificación del historial, además de los bloques de clínicas y atención. (José Aránguiz)

