# Ejecutar en Windows
Requisitos: Git, Flutter en PATH y Edge. Android Studio solo para Android. No se necesita Docker.
Abre PowerShell en la carpeta de proyectos:
```powershell
git clone --branch fase-1/interfaz-base https://github.com/JoseArgz8658/vitalia-health-capstone-prueba.git
cd vitalia-health-capstone-prueba
flutter --version
flutter doctor
cd apps\vitalia
flutter pub get
flutter analyze
flutter run -d edge
```
Esperado: tarjeta de entrada, tres roles de demostración, navegación entre secciones. Reduce ancho para comprobar navegación inferior.
## Android una sola vez
Desde la raíz:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\preparar-android.ps1
cd apps\vitalia
flutter pub get
flutter emulators
flutter emulators --launch ID_DEL_EMULADOR
```
Sustituye el ID por el mostrado. Espera a que Android inicie:
```powershell
flutter devices
flutter run -d ID_DEL_DISPOSITIVO
```
Usa el ID del dispositivo activo. Si android ya existe, omite el script. No ejecutes flutter create . sobre código existente.
No subas .env, local.properties ni claves de firma.
