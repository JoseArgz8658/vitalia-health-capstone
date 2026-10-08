# S3 privado — preparación del almacenamiento

Esta entrega añade el SDK, configuración y operaciones internas. No monta rutas de documentos
ni cambia Flutter. Las pruebas usan un cliente simulado; no equivalen a una conexión con AWS.

## 1. Comprobar código, desde backend
```powershell
npm ci
npm run check
npm test
```
Resultados de desarrollo: compilación correcta y 93 pruebas aprobadas.

## 2. Cuenta y bucket
Si no tienes cuenta AWS o acceso institucional, coordina primero la cuenta y el presupuesto del proyecto.
Este paso usa AWS real: revisa las condiciones de facturación de tu cuenta antes de crear recursos.
No presupone gratuidad ni crea recursos por ejecutar npm test.

En una cuenta de desarrollo autorizada:
1. Abre Amazon S3 en la consola de AWS.
2. Create bucket → General purpose. Usa un nombre único, sin nombres de pacientes.
3. Selecciona y anota la región. Debe coincidir con AWS_REGION.
4. Object Ownership: Bucket owner enforced / ACLs disabled.
5. Block Public Access: mantén las cuatro casillas activadas.
6. Default encryption: SSE-S3.
7. Para esta prueba no necesitas activar hosting web, Object Lock ni configurar CORS del bucket.
8. Crea el bucket. No agregues una política de lectura pública.

El módulo requiere nombres con letras minúsculas, números y guiones, sin puntos.
La comprobación requiere ACL deshabilitadas y los cuatro bloqueos públicos en el propio bucket.
Esto no sustituye revisar otras concesiones IAM o accesos entre cuentas.

Referencia: https://docs.aws.amazon.com/AmazonS3/latest/userguide/create-bucket-overview.html

## 3. Permisos de la identidad del backend
Usa una identidad de desarrollo dedicada, nunca claves del usuario raíz.
El administrador de la cuenta puede adjuntar la política de ejemplo
backend/config/s3-policy.example.json a un rol o usuario IAM del backend.
Antes debe sustituir REPLACE_WITH_BUCKET por el nombre real del bucket en los dos recursos.
La política no otorga permiso para crear buckets o cambiar su privacidad.
Si existe IAM Identity Center, prefiere su sesión temporal con un perfil local.

### Perfil con IAM Identity Center existente
Instala AWS CLI v2 desde https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
Abre otra terminal después de instalar y verifica:
```powershell
aws --version
aws configure sso --profile vitalia-dev
aws sso login --profile vitalia-dev
```
El administrador debe proporcionarte Start URL o Issuer URL, región SSO y acceso al rol.
No habilites Identity Center solo para seguir esta opción si tu cuenta todavía no lo tiene configurado.

### Perfil IAM para una cuenta sin Identity Center
El administrador crea un usuario IAM dedicado sin acceso a la consola, adjunta la política limitada
y genera una access key para desarrollo local. Con AWS CLI v2:
```powershell
aws configure --profile vitalia-dev
```
Ingresa Access Key ID y Secret Access Key solo en los prompts de tu computador, región del bucket y formato json.
AWS CLI guarda las credenciales fuera del repositorio, en el perfil del usuario Windows.
No pegues claves en comandos, documentos del proyecto, capturas o mensajes.

Referencia de proveedores:
https://docs.aws.amazon.com/sdk-for-javascript/v3/developer-guide/setting-credentials-node.html

## 4. Configurar backend/.env
Añade al .env actual, conservando PostgreSQL:
```dotenv
AWS_REGION=REGION_DEL_BUCKET
S3_BUCKET=NOMBRE_REAL_DEL_BUCKET
AWS_PROFILE=vitalia-dev
```
Los valores en mayúscula son marcadores, no valores para copiar literalmente.
No pongas las claves en .env.example. No subas .env.

## 5. Comprobar, desde backend
```powershell
npm run build
node --env-file=.env dist/storage/check.js
```
Resultado esperado:
Conexión a S3 correcta. Bloqueo público y ACL deshabilitadas comprobados.

Este comando consulta el bucket y sus controles; no sube ni elimina objetos.
Si falla, comparte solo el mensaje y código técnico, sin credenciales.
AccessDenied: revisar política y bucket real. CredentialsProviderError: revisar perfil o sesión SSO.
NoSuchBucket: revisar nombre. Un Error genérico puede corresponder a configuración o controles de privacidad.

## Alcance pendiente
Las operaciones put/get/delete son internas. No aplican por sí solas permisos por paciente.
La futura API deberá confirmar sesión y propiedad con PostgreSQL antes de llamarlas.
El módulo valida tamaño y MIME declarado; falta validar el contenido real, auditoría y manejo
de fallos entre S3 y PostgreSQL. Todavía no se puede cargar un examen desde Flutter.
