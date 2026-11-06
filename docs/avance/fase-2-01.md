# Fase 2 Incremento 01
Paleta autorizada azul #2867B2, verde #39A59A, fondo #EAF2FB, blanco #FFFFFF, texto #263238, borde #D7E0E5.
Añadidos entrada main_fase2.dart, tema reutilizable, datos sintéticos, consulta/historial ordenados, búsqueda, filtros por tipo/fecha y detalle.
No se modificó ni eliminó código previo. No hay sesión, archivos subidos, S3, backend ni IA.
Fase 2 en curso: pendientes carga visual y flujos profesional/administración.
Validación pendiente en equipo del usuario: este entorno no dispone de Flutter.
Desde la raíz con git status limpio:
git fetch origin
git switch --track origin/fase-2/examenes-historial
Si la rama ya existe localmente: git switch fase-2/examenes-historial y git pull --ff-only.
Desde apps/vitalia:
flutter pub get
flutter analyze
flutter run -d edge -t lib/main_fase2.dart
Comprobar: 3 exámenes iniciales, filtro Laboratorio muestra 2, búsqueda inexistente muestra vacío, fechas acotan registros, detalle y volver funcionan, historial descendente, ancho estrecho sin desbordes.
main.dart conserva la demostración de fase 1.
