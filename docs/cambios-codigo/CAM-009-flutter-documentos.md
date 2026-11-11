# CAM-009 — Documentos en Flutter
Autorización explícita del usuario para dos archivos existentes, 1 de octubre de 2026.

- vitalia_mvp_app.dart: paciente autenticado abre panel de documentos; otros roles conservan vista de cuenta.
- auth_api.dart: transporte autenticado de documentos, validación de destino y descarte de sesión ante 401.
Archivos nuevos: panel, carga, modelo, cliente, descarga, pruebas y guía.
Sin cambios en dependencias, backend, AWS o .env. Se conservan las vistas demostrativas.

Consecuencias: los archivos cargados por el usuario quedan persistidos; ya no son registros en memoria.
El historial se obtiene únicamente del backend. Descarga autenticada sin URL pública.
Carga de hasta 10 MiB, MIME y extensión conocidos; firmas verificadas por backend.
El formulario vive dentro del panel, de modo que expiración/logout retiran el flujo del paciente.
Cada solicitud usa la sesión en memoria; una respuesta de una sesión anterior se rechaza.

Verificación: compatibilidad multipart comprobada con backend, incluidos nombres Unicode.
Flutter/Dart no disponibles aquí: análisis, pruebas nuevas y revisión visual pendientes.
Descarga Android/iOS pendiente; Edge local es la ruta de comprobación actual.
Reversión: volver a fase-4/api-documentos. No se borran documentos almacenados al revertir código.
