# Fase 2 Incremento 08
Entrada habitual main.dart y main_vitalia.dart abren acceso sin demo.
Formulario valida datos ficticios pero no concede acceso; backend pendiente.
Vistas anteriores conservadas para desarrollo; fuera de navegación MVP.
Desde raíz con git status limpio:
git fetch origin
git switch --track origin/fase-2/acceso-mvp
Desde apps/vitalia:
flutter pub get
flutter analyze
flutter test
flutter run -d edge
Esperado: solo formulario, sin Explorar demostración ni elección de roles. Datos ficticios válidos informan servicio pendiente; no navega.
Para compilar entrega usar flutter build web (main.dart por defecto), sin -t apuntando a entradas demo.
El asistente no tiene Flutter: pruebas pendientes de ejecución local. Backend/auth será siguiente etapa.
