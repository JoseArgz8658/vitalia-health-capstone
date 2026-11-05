# Cuentas y roles — fase 3.4

Requiere haber comprobado PostgreSQL con docs/postgresql-local.md. Usa la misma base vitalia_dev y el mismo .env local. No cambies contraseñas ni recrees la base.

## Qué se añade
| Tabla | Función |
| --- | --- |
| public.vitalia_roles | Catálogo de paciente, profesional y administrador |
| public.vitalia_accounts | UUID, correo normalizado y único, hash, rol y fecha de creación |
| public.vitalia_schema_migrations | Versión, huella y fecha de migración |

Los códigos internos son paciente, profesional y administrador. La migración solo llena el catálogo de roles; no crea usuarios de acceso.
Este es el modelo mínimo de acceso, no el modelo clínico completo. Los perfiles de pacientes y profesionales, asociaciones y exámenes vendrán después.
Las funciones nuevas de persistencia están en backend/src/accounts/repository.ts. La creación actual fija el rol paciente y devuelve un resumen sin hash. La consulta de credenciales es exclusivamente interna y no debe enviarse como respuesta de una API.
No hay endpoint de registro, sesiones ni pantallas de autenticación conectadas.

## 1. Obtener la rama y verificar el código
Desde la raíz del repositorio, ejecuta git status y guarda cambios propios antes de cambiar de rama:
```powershell
git fetch origin
git switch fase-3/cuentas-persistentes
cd backend
npm ci
npm run check
npm test
```
Resultado esperado: cinco suites y 32 pruebas aprobadas.
No hay dependencias nuevas ni cambios de package-lock.json. El .env se conserva localmente al cambiar de rama.

## 2. Aplicar la migración en tu base de desarrollo
Comprueba que PostgreSQL esté activo y que .env apunte a vitalia_dev, la base exclusiva de desarrollo de Vitalia.
Desde backend:
```powershell
npm run build
node --env-file=.env dist/database/check.js
node --env-file=.env dist/database/migrate-accounts.js
```
La migración crea las tablas anteriores y registra su versión dentro de una transacción. No borra tablas ni cuentas existentes.
Salida esperada:
```text
Migración de cuentas aplicada.
```
Puedes volver a ejecutar exactamente el último comando. Debe mostrar:
```text
La migración de cuentas ya estaba aplicada.
```
No volverá a insertar los roles ni ejecutará el DDL ya registrado.
Si encuentra una migración aplicada con otra huella, se detiene. No edites el archivo SQL ya aplicado: los cambios futuros se harán mediante otra migración autorizada.
La huella normaliza saltos de línea LF/CRLF para que el cambio de sistema operativo no invalide el archivo.

## 3. Verificar persistencia real sin dejar una cuenta de prueba
```powershell
node --env-file=.env dist/database/verify-accounts.js
```
Salida esperada:
```text
Persistencia de cuentas correcta. La cuenta sintética fue revertida.
```
La prueba genera correo y contraseña sintéticos en memoria, guarda la cuenta, la consulta y comprueba la contraseña correcta y una incorrecta. Luego revierte la transacción y comprueba que la cuenta ya no exista.
No imprime correo, contraseña ni hash. No crea cuentas reales ni inicia sesiones.
Después de cada comando puedes ejecutar:
```powershell
$LASTEXITCODE
```
0 indica éxito; 1 indica fallo.

## 4. Ver las tablas en pgAdmin
1. Abre pgAdmin y la conexión local que ya configuraste.
2. Expande Databases → vitalia_dev → Schemas → public → Tables.
3. Clic derecho en Tables → Refresh.
4. Deben aparecer vitalia_roles, vitalia_accounts y vitalia_schema_migrations.
No necesitas modificar ni eliminar filas para comprobar este incremento.

## Si falla
- Comprueba primero el comando dist/database/check.js.
- Si falla la migración, verifica que uses la base del proyecto y el usuario propietario vitalia_app indicado en la guía anterior.
- Si ya hay tablas con los mismos nombres pero no una migración registrada, el comando no las sobrescribirá. Comparte el mensaje y detente; no borres tablas para forzar la instalación.
- Si la verificación falla, confirma que la migración fue aplicada antes.
- Comparte solo los mensajes y códigos de salida. No envíes .env, contraseñas ni hashes.

## Estado y referencias
La compilación y las pruebas automatizadas verifican el código y sus contratos con dobles de base. La aplicación de la migración y la prueba real de persistencia quedan pendientes del equipo del usuario.
Fuentes técnicas:
https://www.postgresql.org/docs/16/ddl-constraints.html
https://node-postgres.com/features/transactions
