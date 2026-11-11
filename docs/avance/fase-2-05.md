# Fase 2 Incremento 05
Selector real local con file_selector 1.1.0, nombre/tamaño, cancelación, quitar selección, rechazo de archivo vacío y error controlado.
Sin restricciones de formatos/tamaño inventadas. No es carga real ni valida contenido.
Nuevo main_archivos.dart, vista anterior accesible mediante botón. Modificación autorizada pubspec registrada CAM-001.
Lockfile todavía requiere regeneración local con pub get; no actualizar paquetes mediante pub upgrade.
Desde raíz, árbol limpio:
git fetch origin
git switch --track origin/fase-2/seleccion-archivos
Desde apps/vitalia:
flutter pub get
flutter analyze
flutter run -d edge -t lib/main_archivos.dart
Pruebas: elegir archivo sintético, nombre y bytes, cancelar conservando anterior, quitar, archivo vacío rechazado, navegación previa y ancho móvil.
Para Android: flutter run -d ID_DISPOSITIVO -t lib/main_archivos.dart después de arrancar emulador y preparar Android si no existe.
Revisar git diff pubspec.lock y git status. Guardar lock actualizado con git add pubspec.lock y git commit -m "chore: fijar dependencias del selector" y git push.
Si aparecen registros generados de plugins, revisar sus rutas; no incluir local.properties, secretos o archivos elegidos.
Ejecución pendiente de equipo usuario; fase 2 no finalizada.
