# Fase 2 Incremento 03
Base: fase-2/registro-examenes. Usuario confirmó ejecución del incremento anterior.
Añadidos selector de roles, consulta profesional de dos pacientes ficticios y sus exámenes, administración de solo lectura con búsqueda de usuarios, resumen de permisos y evento sintético de auditoría.
Reutilizados tema, panel paciente y detalle existentes. Ningún archivo previo modificado.
Colecciones profesionales independientes del registro local del paciente: sincronización pendiente del backend.
No hay login, asignación de permisos, revisión IA, auditoría real ni archivos almacenados.
Fase 2 sigue en curso; selección de archivos y acceso visual pendientes.
Verificación de ejecución pendiente en equipo usuario.
Con árbol limpio desde raíz:
git fetch origin
git switch --track origin/fase-2/vistas-profesional-admin
Desde apps/vitalia:
flutter pub get
flutter analyze
flutter run -d edge -t lib/main_roles.dart
Pruebas: abrir tres roles; paciente conserva registro local; profesional buscar, abrir paciente 001 y detalle, paciente 002 vacío; administrador buscar y alternar secciones; volver al selector; probar ancho móvil.
