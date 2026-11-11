# CAM-006 — Conexión Flutter y acceso real

Autorizado por el usuario el 1 de octubre de 2026.

## Archivos existentes
- acceso_page.dart: reemplaza validación demostrativa por login y enlace de registro.
- vitalia_mvp_app.dart: sesión en memoria, identidad confirmada con GET /me, caducidad y logout.
- pubspec.yaml y pubspec.lock: http 1.6.0 pasa de dependencia transitiva a directa; se conserva la versión y huella ya fijadas.
- backend/src/app.ts: incorpora CORS local mediante módulo nuevo.

## Archivos nuevos
Cliente de autenticación, formulario de registro, middleware CORS, pruebas y guía local.

## Consecuencias y alcance
El registro crea cuentas persistentes de paciente. No concede roles privilegiados ni abre automáticamente una sesión.
No se almacena el token en disco ni en localStorage. La recarga requiere login.
La vista autenticada muestra únicamente la cuenta y el rol devueltos por /me. No conecta los paneles demostrativos ni sus datos médicos ficticios.
Expiración local basada en expiresAt y nueva comprobación al reanudar. El backend sigue siendo la autoridad para cada operación.
Logout solicita revocación; si falla la red descarta el token local y avisa que no se confirmó la revocación remota.
CORS admite exactamente http://localhost:5173, sin comodines. Es configuración local; despliegue requiere definir sus orígenes.
No se eliminaron archivos anteriores ni se modificaron las pruebas históricas de la maqueta.

## Verificación
TypeScript y 78 pruebas del backend aprobadas.
Flutter no está instalado en este entorno: análisis, pruebas nuevas y ejecución visual pendientes en el computador del usuario.
