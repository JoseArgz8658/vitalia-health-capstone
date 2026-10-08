# CAM-029 — Consulta profesional

Autorización: «autorizo todo aquello» para migración 008, módulos/pantallas/pruebas y cambios de app.ts, server.ts, auth_api.dart y asignaciones_page.dart.

Cambios existentes: montaje y conexión del servicio profesional; comprobación de tabla de auditoría 008 al inicio; cliente de solicitudes GET acotado al origen y rutas profesionales; selección de paciente y vista de exámenes integrada en el contenedor autenticado.

Nuevos: migración de auditoría, servicio/router, comandos de migración y verificación, API/página/panel Flutter, pruebas y documentos. Sin dependencias nuevas ni modificación de datos existentes, procesamiento o roles.

Permite historial, descarga y consulta de extracción solo con relación activa. Registra cada acceso autorizado. Descargar valida objeto y revalida permisos tras S3. No habilita edición ni aprobación. Las extracciones se presentan sin normalizar datos.

Validación: compilación y 246 pruebas backend en 31 suites. Cobertura de rol, asignación, documento ajeno, desactivación durante S3, contenido/tamaño incorrecto, auditoría fallida, estado sin trabajo y rechazo de escritura. Flutter añadido pero pendiente en Windows; verificación PostgreSQL preparada con datos sintéticos revertidos y S3 sustituido.

Reversión: restaurar los cuatro archivos existentes desde fase-5/asignaciones-pacientes y retirar módulos nuevos de esta consulta. Conservar migración 008 y eventos si ya aplicada: retirar código no revierte datos ni borra archivos descargados. No editar migraciones aplicadas ni eliminar auditoría.
