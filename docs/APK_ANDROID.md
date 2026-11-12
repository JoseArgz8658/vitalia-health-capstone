# APK de Vitalia Health: compilación y pruebas Android

## Objetivo

Instalar la misma aplicación Flutter SIL principal en un teléfono Android, con autenticación por roles y conexión HTTPS a la API central. La APK es un cliente; el backend y PostgreSQL siguen ejecutándose en el servidor.

## Método A: compilación automatizada

1. Abrir GitHub Actions y seleccionar la ejecución **Vitalia Android - APK de pruebas** correspondiente a la rama/PR.
2. Comprobar que el job terminó con estado `success`.
3. Descargar el artefacto `vitalia-android-sil-apk-privada`, extraer `app-debug.apk` del ZIP e instalarlo en Android aceptando la instalación desde la fuente elegida.
4. La APK de esta canalización está configurada contra `https://beowulf.tail5c0c9b.ts.net`, que es **Serve privado**, por lo que el teléfono debe tener acceso autorizado a Beowulf mediante Tailscale. La APK no hace público el backend.

## Método B: compilar en Windows

En una máquina con Flutter, Java/Android SDK y licencias correctas:

```powershell
cd C:\Users\dpalm\Documents\vitalia-health-git
git switch develop
git pull --ff-only origin develop
cd apps\vitalia
flutter doctor -v
flutter pub get
flutter build apk --debug `
  --dart-define=VITALIA_SIL_MAIN_MODE=true `
  --dart-define=VITALIA_API_URL=https://beowulf.tail5c0c9b.ts.net
```

Archivo generado: `apps/vitalia/build/app/outputs/flutter-apk/app-debug.apk`.

## Acceso desde celular sin Tailscale

Se requiere un endpoint HTTPS público **aislado y protegido**, distinto de la base operativa de Beowulf. No se recomienda fijar Funnel al mismo `127.0.0.1:5173` usado por la instalación principal. Una vez creado el endpoint de pruebas, se recompila cambiando `VITALIA_API_URL` por su URL autorizada. El valor se incorpora a la APK en la compilación.

## Límites

- La compilación automatizada no constituye prueba funcional en un dispositivo físico; validar acceso, navegación por rol, descarga de PDF, rotación, tamaños y cierre de sesión.
- Las credenciales no se incluyen en la APK. No incorporar secretos en `--dart-define` ni subir `.env`.
- El APK de pruebas utiliza firma de depuración. Para distribuir formalmente se requiere firma de lanzamiento propia, versionado y pruebas adicionales.
- No instalar aplicaciones de origen desconocido sin verificar la procedencia del archivo y su integridad.