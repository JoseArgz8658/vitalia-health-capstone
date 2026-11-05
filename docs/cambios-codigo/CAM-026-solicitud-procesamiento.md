# CAM-026 — Solicitud y estado de procesamiento en el historial

Autorización explícita del usuario: «autorizo todo ello», tras detallar las modificaciones de app.ts, server.ts, auth_api.dart y paciente_documentos_page.dart y la creación de módulos y pruebas.

Cambios existentes: app.ts monta el router opcional de procesamiento; server.ts conecta su servicio a PostgreSQL y comprueba la tabla de migración 006; auth_api.dart permite el sufijo processing con sesión y origen controlados; paciente_documentos_page.dart incluye un panel independiente por documento.

Archivos nuevos: servicio y router backend, pruebas HTTP, cliente y panel Flutter, pruebas Flutter y documentación. No hay cambios de esquema ni dependencias.

Consecuencia: el paciente puede reservar un trabajo de su documento y consultar estado y fechas. La ejecución continúa con el comando manual. Se preservan resultados terminales y no se muestran extracciones pendientes de revisión. Las rutas no conceden acceso a profesionales/administradores.

Validación: compilación TypeScript y 202 pruebas backend en 27 suites. Las nuevas pruebas cubren sesión, roles, propiedad, solicitudes concurrentes, estados terminales, cuerpos extra y errores sin detalles internos. Flutter SDK no está disponible en el entorno de implementación: pruebas añadidas pero pendientes de ejecución local junto con flutter analyze.

Reversión: restaurar los cuatro archivos existentes desde la rama fase-5/procesador-manual y retirar los archivos nuevos de esta integración. No retirar el procesador manual ni la migración 006. Los trabajos ya reservados permanecen en PostgreSQL; revertir código no elimina datos.
