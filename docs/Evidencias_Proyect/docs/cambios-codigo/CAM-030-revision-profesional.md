# CAM-030 — Revisión profesional

Autorización: «autorizo aquello» tras detallar migración 009, módulos/formulario/pruebas y cambios de conexiones backend, auth_api.dart, pantalla/panel profesional y estado del paciente.

Se modifican app.ts y server.ts para conectar revisión y exigir tabla 009; processing/service.ts agrega solo metadata de revisión al estado propio del paciente; auth_api.dart añade solicitudes de revisión con sesión, origen y ruta controlados. Flutter conecta formulario a profesional_documentos_page.dart, distingue copia revisada en extraccion_panel.dart y agrega estado registrado en procesamiento_api.dart/procesamiento_panel.dart. Se ajusta processing-api.test.cjs para el contrato ampliado.

Se crean migración 009, servicio/router, migrador/verificador PostgreSQL, API/formulario y pruebas de revisión, guía y resumen de fase. No se agregan dependencias ni se modifica la extracción original, el procesamiento, documentos S3 o roles.

Aprobación explícita con asignación activa, confirmación original, calendario válido y observaciones ante cambios/datos ausentes. Una copia humana por procesamiento; bloqueo y restricción única evitan sobrescritura y el trigger impide UPDATE/DELETE. No hay borradores, rectificaciones o anulación posterior en este alcance. Paciente ve solo estado, no resultados todavía.

Validación: compilación y 268 pruebas backend en 32 suites. Cubren original intacto, correcciones, ausencias/ceros, calendario, rol, revocación, duplicados, procesamiento incompatible y estado propio del paciente. Verificador de DB preparado con rollback y prueba de trigger mediante savepoints. Flutter añadido pero pendiente en Windows; sin SDK aquí.

Reversión: restaurar archivos existentes desde fase-5/consulta-profesional y retirar módulos/UI nuevos. Conservar 009 y revisiones/auditoría si ya aplicada; retirar código no revierte datos ni permite eliminar registros aprobados. No editar migraciones anteriores ni eliminar triggers o revisiones para corregir pruebas.
