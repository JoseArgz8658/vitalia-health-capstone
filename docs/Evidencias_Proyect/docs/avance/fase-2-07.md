# Fase 2 Incremento 07
Portal único main_vitalia.dart reúne acceso visual, paciente con archivos asociados, profesional, administrador e historial filtrado inicial.
Reutiliza pantallas anteriores sin alterar su código. El formulario de acceso mantiene navegación anterior: no autentica ni asigna roles.
Datos locales no sincronizados; el historial inicial sigue siendo una colección sintética separada.
Nuevas pruebas widget de navegación al registro, retorno y administración en ancho estrecho.
No se afirma fase completa ni pruebas aprobadas hasta ejecutarlas.
Con árbol limpio en raíz:
git fetch origin
git switch --track origin/fase-2/flujo-unificado
Desde apps/vitalia:
flutter pub get
flutter analyze
flutter test test/portal_demo_test.dart
flutter run -d edge -t lib/main_vitalia.dart
Verificar portal, acceso, 3 roles, volver, historial inicial, registrar documento, vista estrecha.
No hay SDK Flutter en entorno asistente: analyze/tests/ejecución pendientes en equipo usuario.
Próximo: acordar formatos/límite y consolidar flujo antes de backend. Para sustituir main.dart o modificar pantallas existentes se necesita autorización.
