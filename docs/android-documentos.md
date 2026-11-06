# Android: registro, exámenes y descarga

Rama fase-4/android-documentos. El backend ya funciona con PostgreSQL y S3.

## Qué hace preparar-android.ps1
Genera una plantilla Flutter Android en una carpeta temporal, con organización cl.vitalia
y proyecto vitalia_health. Copia solo android a apps/vitalia y elimina la plantilla temporal.
No toca lib ni web. Si android ya existe, el script original se detiene.

## 1. Preparar Android — desde la raíz
Guarda cambios locales y detén Flutter.
```powershell
git fetch origin
git switch fase-4/android-documentos
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configurar-android-documentos.ps1
```
El nuevo script llama al anterior si falta android, después configura descarga y red debug.
Resultado esperado:
Android preparado: descarga con selector y HTTP local debug para 10.0.2.2.
También muestra la ubicación del respaldo fuera del repositorio.

Comprueba que MainActivity sea una plantilla original o idéntica a nuestra integración.
Si encuentra cambios no reconocidos, se detiene; no fuerces reemplazos.
La configuración de HTTP se añade solo bajo src/debug. No habilita HTTP en release.

## 2. Backend — otra terminal desde raíz
PostgreSQL debe estar activo. Conserva el perfil AWS y .env actuales.
```powershell
cd backend
npm start
```
Deja esta terminal abierta.

## 3. Revisar Flutter — desde raíz en otra terminal
```powershell
cd apps\vitalia
flutter pub get
flutter doctor
flutter analyze
flutter test test/auth_api_test.dart test/acceso_integrado_test.dart test/documentos_api_test.dart test/paciente_documentos_test.dart test/guardar_documento_android_test.dart
flutter emulators
```
Si flutter doctor muestra un problema en Android toolchain, comparte ese apartado antes de continuar.
Si aún no tienes un dispositivo virtual: Android Studio → Device Manager → Create Device →
elige un teléfono, una imagen Android disponible y termina el asistente.

## 4. Abrir emulador
Sustituye ID_DEL_EMULADOR por el ID mostrado en flutter emulators:
```powershell
flutter emulators --launch ID_DEL_EMULADOR
```
Espera a que aparezca la pantalla Android y ejecuta:
```powershell
flutter devices
```
Usa el ID del dispositivo activo, por ejemplo emulator-5554:
```powershell
flutter run -d emulator-5554 --dart-define=VITALIA_API_URL=http://10.0.2.2:3000
```
El comando es para un emulador Android del computador; no para un teléfono físico.
10.0.2.2 dirige al backend del computador. No cambies HOST=127.0.0.1.

## 5. Probar
- Ingresar con la cuenta paciente usada en Edge. Debe aparecer el mismo historial.
- Descargar un archivo: Android abre el selector de destino. Elegir Downloads y guardar.
- Cancelar otra descarga: no debe mostrar éxito.
- Subir documento ficticio: arrastra un PDF o imagen desde Windows al emulador para copiarlo;
  en la app usa Seleccionar archivo y busca Downloads.
- Actualizar Edge: debe aparecer el documento subido desde Android.
- Cerrar sesión y probar otra cuenta: no debe mostrar documentos ajenos.
Usa únicamente documentos sintéticos o correctamente anonimizados.
La descarga usa ACTION_CREATE_DOCUMENT; no necesita permiso general de almacenamiento.

## Evidencia y límites
Verificación local de sintaxis Dart/Kotlin y XML válida. Flutter, Android SDK, compilador Kotlin
y PowerShell no disponibles en el entorno del asistente: ejecución del script, análisis,
pruebas y compilación Android pendientes en tu computador.
iOS y teléfono físico no se configuran en este paso. La descarga web conserva su implementación.
No subir local.properties, claves ni .env. Los archivos Android generados deberán revisarse
y versionarse antes de trasladar el proyecto; se conservan plantillas reproducibles en scripts/android.

Referencias:
https://developer.android.com/studio/run/emulator-networking-address
https://developer.android.com/training/data-storage/shared/documents-files
https://developer.android.com/privacy-and-security/security-config
