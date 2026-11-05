# Flutter y acceso local

Rama: fase-4/flutter-acceso. No necesita nueva migración ni cambios de .env.
Conserva el .env privado de backend. PostgreSQL debe estar Running.

## Terminal 1: backend, desde la raíz
```powershell
cd backend
npm ci
npm run check
npm test
npm start
```

## Terminal 2: Flutter, desde la raíz
```powershell
cd apps\vitalia
flutter pub get
flutter analyze
flutter test test/auth_api_test.dart test/acceso_integrado_test.dart
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

Usa exactamente localhost:5173; otro origen será rechazado. Si el puerto está ocupado, detén la instancia anterior.
Se mantienen las pruebas históricas de la maqueta sin cambios: algunas comprobaban mensajes del formulario antiguo. Ejecuta las nuevas pruebas indicadas para este flujo; la actualización de esos archivos históricos queda pendiente.
No se ejecutó Flutter en el entorno de desarrollo del asistente.

## Comprobación manual
1. Acceso inicial sin selector de rol.
2. Crear cuenta de paciente con correo de prueba y contraseña ficticia de 12 o más caracteres; confirmar contraseña.
3. Respuesta neutral: no afirma si el correo existía. Volver al acceso.
4. Iniciar sesión con la misma cuenta: aparece el correo y Cuenta: paciente.
5. Comprobar sesión y cerrar sesión.
6. Probar contraseña incorrecta: debe permanecer en el formulario.
7. Detener backend: debe mostrar error de conexión sin conceder sesión.
8. Recargar navegador: vuelve al acceso.
9. Revisar ventana estrecha: formulario desplazable sin desbordamientos.

El registro manual deja una cuenta persistente. Las cuentas sintéticas de los scripts anteriores se revertían y no sirven para ingresar.
La vista de cuenta autenticada es el paso de integración; la gestión de exámenes aún está pendiente.
Esta entrega verifica web local en Edge. Android requiere configuración propia de red y manifiesto antes de probar HTTP local; no se modificaron esos archivos.
