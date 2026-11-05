# Fase 2 Incremento 02
Confirmado pubspec.lock en la rama base; se conserva sin modificaciones.
Añadidos formulario de metadatos de demostración con nombre/tipo/fecha obligatorios, rechazo de fecha futura en selector, cancelación, registro en memoria, búsqueda, historial ordenado y reutilización del detalle anterior.
No es una carga de archivos: no hay selector, bytes, validación MIME, servidor ni persistencia.
La consulta anterior mantiene sus datos iniciales; los registros nuevos solo se muestran en el panel de este incremento.
Únicamente archivos nuevos, entrada main_registro.dart. Fase 2 sigue en curso.
Validación Flutter pendiente en computador del usuario.
Desde raíz con árbol limpio:
git fetch origin
git switch --track origin/fase-2/registro-examenes
Desde apps/vitalia:
flutter pub get
flutter analyze
flutter run -d edge -t lib/main_registro.dart
Comprobar guardar vacío muestra errores; registrar datos ficticios añade un elemento; cancelar no añade; buscar y abrir detalle; historial ordenado; reiniciar pierde registros nuevos; comprobar ancho móvil.
