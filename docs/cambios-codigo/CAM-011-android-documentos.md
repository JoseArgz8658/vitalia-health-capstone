# CAM-011 — Descarga Android y conexión al emulador
Autorización explícita del usuario para guardar_documento.dart, MainActivity generada y manifiesto de desarrollo.
El usuario confirmó que todavía no existe android en apps/vitalia y no había ejecutado preparar-android.ps1.

Cambio existente en repositorio: guardar_documento.dart usa MethodChannel para guardar en Android.
Archivos nuevos: plantillas Kotlin/XML, script de configuración con validación y respaldo, pruebas y guía.
El script original preparar-android.ps1 queda intacto. Se usa para generar la carpeta ausente.
Los cambios locales autorizados se aplican en MainActivity.kt y AndroidManifest.xml bajo src/debug.
Configuración de red debug permite HTTP solo a 10.0.2.2. No modifica release ni dependencias.

Descarga con selector del sistema, límite 10 MiB y errores/cancelación controlados.
No se requieren permisos generales para acceso a todo el almacenamiento.

Verificación: sintaxis Dart/Kotlin y XML válidos. Ejecución PowerShell, compilación Android
y pruebas Flutter pendientes en el equipo usuario.
Reversión: volver a fase-4/recuperacion-documentos y restaurar los archivos Android respaldados
en la ubicación mostrada por el script. No borra carpetas Android ni documentos.
