# PostgreSQL local en Windows — fase 3.3

Este incremento conecta el backend con PostgreSQL 16 mediante un comando independiente. No modifica el servidor HTTP ni crea tablas, cuentas de Vitalia o sesiones. /api/health sigue comprobando únicamente el proceso Express.
La configuración actual acepta solo 127.0.0.1, localhost o ::1. La conexión remota y TLS se prepararán en otra fase. No hace falta configurar Amazon S3 ni contratar un servicio.
Las pruebas de Jest usan dobles de conexión y no necesitan una base instalada; la prueba real se ejecuta por separado.

## 1. Descargar el código
Abre PowerShell en la raíz de vitalia-health-capstone-prueba.
Ejecuta git status; si muestra cambios propios, guárdalos antes de cambiar de rama. Luego:
```powershell
git fetch origin
git switch fase-3/conexion-postgresql
cd backend
npm ci
npm run check
npm test
```
Resultado esperado: tres suites y 17 pruebas aprobadas. npm test también compila en dist.
El package-lock.json ya está actualizado y versionado en esta rama; no necesitas regenerarlo.

## 2. Instalar PostgreSQL 16 si todavía no lo tienes
1. Abre https://www.postgresql.org/download/windows/ y pulsa Download the installer. El sitio oficial deriva al instalador de EDB.
2. En EDB elige la versión estable disponible de la serie 16 para Windows x86-64. No elijas beta. Descárgala y ejecuta el instalador.
3. Conserva la ubicación de instalación predeterminada. En componentes incluye PostgreSQL Server, pgAdmin 4 y Command Line Tools. Stack Builder es opcional y no lo utilizaremos.
4. Conserva el directorio de datos predeterminado.
5. Cuando solicite la contraseña del usuario administrador postgres, crea una y guárdala fuera del repositorio. No me la envíes.
6. Selecciona puerto 5432. Si el instalador indica que ya está ocupado, comprueba si ya tienes PostgreSQL instalado antes de crear otra instancia.
7. Conserva la configuración regional predeterminada y termina la instalación.
8. Si ofrece ejecutar Stack Builder al finalizar, desmarca esa opción: no hacen falta componentes adicionales.
Si ya tienes PostgreSQL 16, utiliza esa instalación sin reinstalar ni borrar bases existentes.
Referencia: https://www.postgresql.org/download/windows/

## 3. Abrir la administración local
1. Abre pgAdmin 4 desde Inicio de Windows.
2. Si solicita una contraseña maestra para pgAdmin, esta protege sus credenciales guardadas y es distinta de la contraseña del usuario postgres.
3. Expande Servers y abre la conexión PostgreSQL 16. Introduce la contraseña postgres elegida durante la instalación.
4. Si no hay conexión registrada: clic derecho en Servers → Register → Server. En General usa el nombre PostgreSQL local. En Connection usa Host 127.0.0.1, Port 5432, Maintenance database postgres y Username postgres. Introduce la contraseña del instalador y guarda.
No compartas capturas que muestren contraseñas.

## 4. Crear el usuario local de la aplicación
La contraseña administrativa postgres no se utilizará en el backend.
1. Dentro del servidor expande Login/Group Roles.
2. Clic derecho → Create → Login/Group Role.
3. En General, Name: vitalia_app.
4. En Definition, Password: elige otra contraseña, distinta de la administrativa. Guárdala fuera del repositorio.
5. En Privileges activa Can login. Mantén desactivados Superuser, Create roles, Create databases, Replication y Bypass RLS.
6. Guarda con Save.
Si vitalia_app ya existe, no lo borres: comprueba que sea el usuario que preparaste para este proyecto.

## 5. Crear una base exclusiva de desarrollo
1. Clic derecho en Databases → Create → Database.
2. En Database escribe vitalia_dev.
3. En Owner selecciona vitalia_app.
4. Conserva las demás opciones y guarda.
Si vitalia_dev ya existe, úsala solo si corresponde a este proyecto; no elimines ni sobrescribas otra base.
En desarrollo el usuario es propietario de su base para las próximas migraciones. Separaremos privilegios de migración y ejecución antes del despliegue.

## 6. Crear la configuración privada
En la terminal situada en backend:
```powershell
if (!(Test-Path .env)) { Copy-Item .env.example .env }
notepad .env
```
En el archivo deja estos valores y sustituye solamente el texto de ejemplo por la contraseña de vitalia_app:
```dotenv
PORT=3000
HOST=127.0.0.1
PGHOST=127.0.0.1
PGPORT=5432
PGDATABASE=vitalia_dev
PGUSER=vitalia_app
PGPASSWORD="REEMPLAZAR_POR_TU_CONTRASEÑA_LOCAL"
```
Las comillas ayudan con espacios y el carácter #. Guarda y cierra el editor. Si tu contraseña incluye comillas o saltos de línea, elige para este entorno una contraseña larga sin esos caracteres para evitar errores de formato.
No modifiques .env.example para introducir credenciales reales.
Comprueba que Git ignore el archivo:
```powershell
git check-ignore .env
git status --short
```
El primer comando debe mostrar .env; el segundo no debe listar .env como archivo para subir. Si no se cumple, detente antes de hacer commit y comparte solo la salida, nunca el contenido del archivo.

## 7. Comprobar la conexión real
Con PostgreSQL activo y desde backend:
```powershell
npm run build
node --env-file=.env dist/database/check.js
```
Debe aparecer:
```text
Conexión con PostgreSQL correcta.
```
El comando termina por sí solo, libera las conexiones y no crea tablas ni modifica datos.
Para comprobar el código de salida:
```powershell
$LASTEXITCODE
```
Debe ser 0. Un error da 1 y un mensaje genérico sin contraseña.

## 8. Si la comprobación falla
1. Revisa que estés en backend y que exista .env.
2. Abre Servicios de Windows y comprueba que el servicio PostgreSQL de tu instalación esté iniciado.
3. Verifica PGHOST y PGPORT con la conexión que funciona en pgAdmin.
4. Revisa PGDATABASE y PGUSER; la contraseña debe ser la de vitalia_app, no la de postgres.
5. Guarda .env y vuelve a ejecutar el comando.
Si necesitas ayuda, comparte el mensaje y el código de salida. No envíes .env ni credenciales.

## 9. Continuar con Express
```powershell
npm start
```
Abre http://127.0.0.1:3000/api/health. Conserva su respuesta anterior. Ctrl+C detiene el servidor.
El servidor HTTP todavía no utiliza el pool: este incremento comprueba y prepara la conexión reutilizable. La persistencia y la integración de autenticación llegarán después con los cambios necesarios autorizados.
