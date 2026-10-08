# Documentos del paciente desde Flutter

Rama fase-4/flutter-documentos.
Cambios existentes autorizados: vitalia_mvp_app.dart y auth_api.dart.
Panel, modelo, cliente de documentos, carga, descarga y pruebas en archivos nuevos.

## Terminal backend, desde raíz
```powershell
cd backend
npm start
```
PostgreSQL Running, perfil vitalia-dev y migración 004_document_audit ya comprobados.
No cambia .env ni requiere otra migración o dependencias nuevas.

## Terminal Flutter, desde raíz
```powershell
cd apps\vitalia
flutter pub get
flutter analyze
flutter test test/auth_api_test.dart test/acceso_integrado_test.dart test/documentos_api_test.dart test/paciente_documentos_test.dart
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

Flutter/Dart no están instalados en el entorno de desarrollo: análisis, tests y revisión visual pendientes en equipo del usuario.
Se mantienen pruebas históricas de maquetas sin modificar; el comando apunta al flujo autenticado.
Se comprobó por separado la compatibilidad del multipart con el backend, incluidos campos, MIME y nombre Unicode.

## Comprobación manual
1. Iniciar sesión con paciente registrado: Mis exámenes, sin datos demostrativos.
2. Subir examen: nombre, Laboratorio/Imagenología, fecha y PDF/JPEG/PNG hasta 10 MiB.
3. Usar solo documentos sintéticos o correctamente anonimizados.
4. Guardar: solo tras respuesta del backend muestra Examen guardado.
5. Consultar tarjeta con nombre, tipo, fecha, archivo y tamaño.
6. Descargar y revisar el archivo local.
7. Recargar navegador, volver a ingresar: el examen debe seguir en historial.
8. Ingresar con un segundo paciente: no debe aparecer el documento del primero.
9. Cerrar sesión: vuelve al acceso.
10. Revisar ventana estrecha: contenido desplazable.
El archivo cargado manualmente queda guardado; no se revierte como los scripts de comprobación.

Historial paginado de 20 documentos y botón de actualización.
Ante timeout o pérdida de conexión durante una carga, actualizar historial antes de repetir:
la operación podría haberse completado en el servidor.
No implementa todavía detección de duplicados o idempotencia de carga.

## Descarga por plataforma
En web, XFile.saveTo inicia una descarga local gestionada por el navegador, sin URL pública S3.
En escritorio compatible, selector de destino para guardar.
Guardar en Android/iOS queda pendiente de integración del mecanismo de descarga móvil.
El despliegue/red Android también requiere su configuración propia; esta entrega se verifica en Edge local.
La IA, revisión profesional y acceso profesional todavía no se incorporan a este panel.
