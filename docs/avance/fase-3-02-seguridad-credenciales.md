# Fase 3.2: protección de credenciales

## Alcance
Funciones nuevas para generar y comprobar hashes de contraseña antes de implementar las cuentas en PostgreSQL. No se modifica ningún archivo funcional previo, dependencia, ruta ni pantalla. Se mantienen las demos hasta la limpieza solicitada por el usuario.

## Archivos
- backend/src/auth/password.ts: hashPassword y verifyPassword con scrypt asíncrono de Node.js.
- backend/test/password.test.cjs: cinco casos de seguridad.

## Decisiones de implementación
Sal aleatoria de 16 bytes; clave derivada de 64 bytes; N=131072, r=8, p=1; memoria máxima 192 MiB por operación. Formato versionado scrypt-v1. La comparación utiliza timingSafeEqual. El hash contiene sal y resultado, nunca la contraseña original. No es cifrado reversible.
El límite técnico es 1024 bytes UTF-8 y se rechaza una entrada mayor, nunca se trunca. Esto no define todavía la política de complejidad del registro. No se eliminan espacios ni se normaliza Unicode.
Las entradas almacenadas malformadas devuelven false antes del cálculo; los fallos internos de crypto se propagan para que una futura capa de servicio rechace la operación.
La comparación constante no garantiza tiempo constante para todo el flujo de autenticación.

## Validación
Pruebas de sal distinta, verificación correcta, rechazo de contraseña incorrecta, conservación de espacios/Unicode, formato inválido y límites.
El servidor actual conserva sus cinco pruebas. Ejecutar npm run check y npm test para comprobar las diez pruebas con el compilador y Jest del proyecto.
La comprobación aislada del módulo en Node.js se registra en el mensaje de entrega; no sustituye la compilación TypeScript ni la suite completa en el equipo del usuario.

## Límites y continuación
Aún no hay cuentas, sesiones, registro ni acceso real. No se envían hashes al cliente ni se registra ninguna contraseña.
Antes de exponer autenticación hay que añadir persistencia PostgreSQL, controles de intentos/concurrencia, permisos y tratamiento neutral de cuentas inexistentes. scrypt consume memoria; no exponer este módulo como endpoint sin dichos controles.
No se requiere cuenta externa, .env ni cambio de package-lock.json.
Siguiente incremento: persistencia de cuentas, con las dependencias y conexiones necesarias sometidas a autorización antes de modificar archivos existentes.

## Referencia
https://nodejs.org/api/crypto.html#cryptoscryptpassword-salt-keylen-options-callback
