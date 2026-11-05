# Fase 2 Incremento 04
Confirmación del usuario: vistas por rol del incremento 03 ejecutadas correctamente.
Añadidos main_acceso.dart y formulario visual de acceso reutilizando tema y selector de roles.
Validaciones: correo obligatorio y formato básico; contraseña obligatoria; visibilidad; aviso de recuperación sin enviar correo; navegación explícita a demostración.
No hay autenticación: validar formato no otorga acceso. No se envían ni persisten campos. Se limpia contraseña tras validación y ambos campos al explorar.
No se implementa registro de cuentas: reglas de creación/verificación pendientes de especificación.
Ningún archivo existente modificado. pubspec y lockfile intactos, sin dependencias nuevas.
Fase 2 sigue en curso, pendiente selección de archivo y unificación de entradas cuando se autorice.
Desde raíz con git status limpio:
git fetch origin
git switch --track origin/fase-2/acceso-visual
Desde apps/vitalia:
flutter pub get
flutter analyze
flutter run -d edge -t lib/main_acceso.dart
Verificar: vacío muestra errores, correo inválido rechazado, correo ficticio válido informa backend pendiente, mostrar/ocultar clave, recuperación explica limitación, explorar abre roles previos; volver y comprobar campos vacíos. Revisar ancho móvil.
Análisis y ejecución pendientes en equipo usuario; no hay Flutter en entorno del asistente.
