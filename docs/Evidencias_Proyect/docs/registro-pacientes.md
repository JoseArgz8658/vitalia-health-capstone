# Registro de pacientes — fase 3.7

Rama fase-3/registro-pacientes. Usa el mismo .env y las migraciones de cuentas/sesiones ya aplicadas.
No añade dependencias ni requiere otra migración.
El usuario autorizó modificar app.ts/server.ts y exigir al menos 12 caracteres al registrar una contraseña.

## 1. Actualizar el código
Desde la raíz del repositorio, guarda cambios propios si git status los muestra:
```powershell
git fetch origin
git switch fase-3/registro-pacientes
cd backend
npm ci
npm run check
npm test
```
Resultado esperado: 13 suites y 74 pruebas aprobadas.

## 2. Comprobar el flujo real de registro y acceso
Con PostgreSQL activo y desde backend:
```powershell
node --env-file=.env dist/database/check.js
node --env-file=.env dist/database/verify-registration-api.js
```
Continúa al segundo comando solo si el primero confirma la conexión.
Resultado esperado:
```text
Registro de pacientes correcto: validación, duplicados y acceso. Datos sintéticos revertidos.
```
El comando abre su propio servidor local en un puerto libre; no requiere npm start.
Comprueba que contraseña corta y campo role sean rechazados, registra una cuenta sintética con correo normalizado, verifica el rol paciente, intenta duplicarla con otra contraseña y comprueba que no cambie. Luego prueba login, identidad y logout.
La prueba revierte cuenta y sesiones. No imprime correos, contraseñas, hashes ni tokens; no deja usuarios permanentes.
La comprobación de duplicados utiliza un savepoint dentro de la transacción sintética para recuperarse del error de unicidad SQL. El servidor normal usa consultas independientes y no necesita ese savepoint externo.

## 3. Servidor habitual
```powershell
npm start
```
Ahora está disponible POST /api/auth/register, además de las tres rutas de acceso anteriores.
Flutter aún no está conectado. Para evitar credenciales en el historial de consola, usa por ahora la prueba sintética anterior; la siguiente fase añadirá los formularios.
Ctrl+C detiene el servidor y cierra PostgreSQL como antes.

## Contrato
Entrada JSON: exclusivamente email y password. No acepta role, nombre, RUT u otros campos no implementados.
Correo validado, recortado y en minúsculas.
Contraseña: al menos 12 caracteres Unicode, máximo técnico 1024 bytes UTF-8, sin exigencia de símbolos. No se recortan espacios ni se modifica su contenido.
Rol: paciente, definido por el servidor mediante la función de persistencia existente.
El registro no entrega un token ni inicia sesión automáticamente; el acceso se realiza con login.

| Estado HTTP | Comportamiento |
| --- | --- |
| 202 | Solicitud procesada; respuesta neutral tanto para correo nuevo como ya registrado |
| 400 | Datos inválidos, contraseña corta o campos adicionales |
| 429 | Límite de peticiones |
| 503 | Cálculo de registro ocupado, permite reintentar |
| 500 | Error interno genérico, sin detalles sensibles |

Respuesta 202:
```json
{"message":"Solicitud de registro procesada."}
```
Una solicitud con correo ya registrado no cambia contraseña, rol ni cuenta. La respuesta idéntica evita revelar su existencia directamente. No garantiza que todo el flujo tenga tiempo constante.
El 202 no indica verificación por correo ni procesamiento en una cola: la operación se ejecuta antes de responder. No se ha implementado envío de mensajes o validación de propiedad del correo.
Cada ruta de registro cuenta diez peticiones por IP/15 minutos, con el mismo limitador existente en una instancia separada del login. El límite es local al proceso; conserva los límites y pendientes de despliegue descritos en docs/acceso-sesiones.md.
Las respuestas usan Cache-Control: no-store. Un registro nunca selecciona privilegios de profesional o administrador.

## Pendientes
Conectar Flutter a los formularios de registro/acceso y a la identidad autenticada.
Definir verificación de correos y creación/validación de cuentas profesionales y administrativas antes de implementarlas.
No se crean perfiles clínicos, relaciones con profesionales ni acceso a exámenes en este paso.
Si PostgreSQL está Stopped, utiliza las instrucciones de inicio del servicio de docs/credenciales-backend.md.
