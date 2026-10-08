# Comprobación de credenciales — fase 3.5

Esta fase añade un servicio interno que consulta PostgreSQL y comprueba la contraseña. No inicia una sesión, no genera tokens y no cambia Flutter ni las rutas HTTP.
No necesita una migración adicional, nuevas dependencias ni cambios en .env.
Solo se añaden archivos. La migración de cuentas anterior debe estar aplicada.

## Ejecutar desde la raíz del repositorio
Guarda primero tus cambios locales si git status muestra archivos pendientes.
```powershell
git fetch origin
git switch fase-3/comprobacion-credenciales
cd backend
npm ci
npm run check
npm test
```
Resultado esperado: seis suites y 39 pruebas aprobadas.

## Comprobar PostgreSQL real
Desde backend, con el mismo .env privado y PostgreSQL activo:
```powershell
node --env-file=.env dist/database/check.js
node --env-file=.env dist/database/verify-credentials.js
```
Continúa con el segundo comando solo si el primero confirma la conexión.
Resultado esperado:
```text
Comprobación de credenciales correcta. La cuenta sintética fue revertida.
```
El comando genera una cuenta sintética en una transacción, comprueba contraseña correcta, incorrecta y cuenta inexistente. Revierte la transacción y comprueba que ya no autentica la cuenta. No deja cuentas permanentes ni imprime correos, contraseñas o hashes.
No lo confundas con un inicio de sesión de usuario: no entrega sesiones ni acceso a pantallas.

## Si PostgreSQL aparece detenido en Windows
En tu terminal habitual:
```powershell
Get-Service postgresql-x64-16
```
Si muestra Stopped:
1. Abre Inicio → PowerShell → Ejecutar como administrador.
2. Acepta el aviso de Windows.
3. Ejecuta:
```powershell
Start-Service postgresql-x64-16
Get-Service postgresql-x64-16
```
Debe mostrar Running. Regresa a la terminal habitual en backend y repite la comprobación.
No hace falta cambiar código, reiniciar la base ni modificar .env.
Si Start-Service falla, comparte su mensaje antes de realizar otros cambios.

## Comportamiento interno
createCredentialAuthenticator se instancia una vez durante el arranque del futuro servidor. Recibe email/password, rechaza campos adicionales y devuelve un resumen sin hash o null para credenciales incorrectas.
Una cuenta inexistente también ejecuta scrypt con un hash ficticio generado al arrancar; reduce diferencias evidentes de trabajo, pero no garantiza tiempos idénticos.
Admite un cálculo de credenciales a la vez por instancia y rechaza trabajo concurrente. No sustituye límites de intentos, medidas contra fuerza bruta ni controles distribuidos.
Errores internos de base se propagan al futuro controlador, que deberá responder genéricamente sin devolver detalles.
No define aún una nueva política de creación de contraseñas: conserva los límites técnicos previos para verificar contraseñas ya almacenadas.

## Próximo paso
Conectar registro/acceso y sesiones al servidor, con validaciones y límites. Antes de modificar app.ts, server.ts, configuración u otras piezas existentes se requiere autorización explícita. Aún no se pueden usar las credenciales desde la pantalla de acceso.
