# Fase 2 Incremento 06
Usuario confirmó selector funcionando.
Integrado seleccionar archivo → comprobar no vacío → formulario existente → confirmar metadatos/archivo → lista temporal → detalle.
Nuevo modelo conserva referencia XFile, no contenido copiado ni almacenado en servidor.
Búsqueda y filtro tipo, orden descendente. Cancelar en cada paso no crea registro. Se bloquea registro simultáneo.
No valida MIME, contenido ni tamaño máximo aún; no declara upload exitoso. Solo datos sintéticos.
Reutiliza formulario/detalle/tema/acceso sin modificaciones.
Limitación: formulario reutilizado describe metadatos de demo sin archivo, pues no se cambia código anterior. La confirmación nueva es donde se asocia el archivo.
No hay sincronización con otros paneles: backend pendiente.
Desde raíz con árbol limpio:
git fetch origin
git switch --track origin/fase-2/registro-con-archivo
Desde apps/vitalia:
flutter pub get
flutter analyze
flutter run -d edge -t lib/main_documentos.dart
Probar cancelar selector, cancelar formulario, cancelar confirmación: lista intacta. Confirmar añade una entrada. Buscar/filtrar, abrir detalle, repetir registro, reiniciar pierde memoria.
No copiar archivos seleccionados al repositorio. Si pub get cambia lock, revisar y guardar lock como en incremento anterior.
Validación Flutter pendiente en computador usuario. Fase 2 sigue en curso.
