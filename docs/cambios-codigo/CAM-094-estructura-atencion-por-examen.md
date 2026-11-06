# CAM-094 — Estructura de atención por examen

Fecha: 29 de octubre de 2026. Repositorio de prueba, rama `fase-7/03-atencion-examen`, continuando la base de `fase-7/02-clinicas-pertenencias`.

## Alcance de este incremento

Inicié el bloque autorizado de atención por examen con su estructura y verificación. Preparé `019_exam_care_reviews` y cuatro tablas nuevas. No conecté todavía servicios ni pantallas; no presento este incremento como la selección del médico ya terminada.

Conservé las asignaciones paciente-profesional, sus auditorías, las revisiones aprobadas y el chat actuales. No convertí documentos históricos a una clínica ni atribuí revisiones anteriores a otro autor. Las cuatro tablas nuevas no conceden por sí mismas acceso a exámenes.

| Tabla | Finalidad |
|---|---|
| vitalia_exam_care | Documento, paciente propietario, clínica, sede opcional, pertenencia responsable, especialidad, origen y estado. |
| vitalia_care_reviews | Revisión inmutable por atención, con autor, original de IA, copia revisada y confirmación. |
| vitalia_exam_referrals | Vínculo trazable entre atención de origen y destino dentro de la misma clínica, con actor y motivo. |
| vitalia_care_audit | Eventos inmutables de solicitud, transición, revisión y derivación. |

El inventario pasa de 40 a 44 tablas y de 18 a 19 migraciones al aplicar 019. Las restricciones compuestas añadidas a documentos y procesamiento comprueban propiedad y correspondencia; no cambian los registros existentes. No modifiqué migraciones aplicadas.

## Reglas preparadas

Definí una atención solicitada o activa por documento mediante índice único parcial. Conservé un responsable por fila: para derivar o pedir otra opinión se crea otra atención, no se reemplaza el responsable histórico. La primera elección y la segunda opinión corresponden al paciente; la derivación corresponde al profesional de la atención de origen.

La pertenencia debe estar activa, en una clínica activa, con rol profesional activo, especialidad vinculada y activa, y perfil profesional marcado como verificado con referencia de registro. La sede opcional debe corresponder a esa clínica y a la pertenencia. Validé los vínculos editables de especialidad y sede al actuar, sin fijarlos como FK históricas: el jefe puede cambiar esos vínculos conservando las revisiones anteriores; una atención pendiente ya no podrá activarse con un vínculo retirado. Una invitación activada no acredita por sí misma la habilitación: los perfiles pendientes siguen pendientes. El flujo administrativo para registrar/verificar las credenciales profesionales debe prepararse antes de publicar el catálogo de profesionales elegibles.

Definí estados requested, active, completed, cancelled y referred. Las transiciones llevan revisión incremental y actor. La finalización requiere una revisión. La cancelación permite después una nueva elección referida a la atención cancelada. No permití borrar atenciones ni reabrir una atención terminal.

Cada revisión nueva pertenece a una atención activa y a su responsable. Comprobé que procesamiento y documento coincidan y que la extracción original coincida con la guardada por el procesamiento. No impuse UNIQUE sobre processing_id en la tabla nueva: una segunda opinión puede conservar otra revisión del mismo procesamiento. Mantuve sin cambios la unicidad y el trigger de las revisiones antiguas. La forma y los límites clínicos completos del JSON continuarán validándose en el servicio antes de habilitar la API.

La derivación exige origen y destino del mismo documento, paciente y clínica. Un constraint trigger diferido exige que el vínculo quede completo en la misma transacción. La revisión previa de una segunda opinión corresponde al mismo documento y paciente y a su atención anterior completada. No habilité acceso automático al contenido de esa revisión para otro médico; esa autorización y la lectura dual con revisiones antiguas siguen pendientes del servicio.

## Auditoría y límites de seguridad

Añadí auditoría automática e inmutable de las operaciones nuevas. Revocé permisos de PUBLIC sobre las tablas nuevas y no concedí permisos nuevos a vitalia_app. No añadí rutas ni modifiqué los controles de acceso actuales. La autorización por sesión, la consulta por documento y el cierre del acceso al derivar se implementarán antes de utilizar estas tablas desde la API.

Los triggers comprueban relaciones y reglas, pero no sustituyen la autorización del servidor ni identifican por sí mismos al usuario de una petición HTTP. En la integración deberé obtener el actor de la sesión y revalidar los estados institucionales bajo bloqueo, incluyendo suspensión y revocación concurrentes. La elección del examen no debe crear una asignación global paciente-profesional.

No cambié aún las dos categorías de carga admitidas por el sistema. La ampliación de categorías y sus menús se realizará junto con el formulario y el catálogo; no cargué nombres de especialidades ni clasifiqué médicos automáticamente a partir del texto de un examen.

## Validación

Comprobé compilación TypeScript y la suite backend, con 651 pruebas en 52 suites. Añadí pruebas de reversión del verificador, fallo de conexión y configuración incorrecta sin exponer credenciales.

Ejecuté la migración en PostgreSQL embebido aislado, comprobé reversión de una migración fallida, repetición sin cambios y rechazo de checksum alterado. Ejecuté 54 comprobaciones con datos sintéticos: propiedad, clínica, sede, especialidad, elegibilidad, responsable único, actor, versiones, estados, original de extracción, autoría, segunda opinión, derivación atómica, cancelación, nueva elección e inmutabilidad. Al terminar quedaron cero atenciones sintéticas. El inventario aislado mostró 44 tablas.

El entorno aislado simula el bloqueo consultivo de migraciones y no sustituye una prueba concurrente real en PostgreSQL 16. La aplicación y verificación en la base local del usuario están pendientes. No modifiqué Flutter en este incremento; no corresponde pedir otra ejecución de su suite por estos archivos.

La guía está en [atención por examen](../fase-7/atencion-por-examen.md). No ejecuté migraciones en la base del usuario ni modifiqué el repositorio oficial.

(José Aránguiz)

## Aplicación local confirmada

Registré el respaldo previo comunicado por el usuario, las 651 pruebas backend aprobadas, la aplicación de 019, sus 54 comprobaciones correctas con datos sintéticos revertidos y el inventario de pgAdmin: vitalia_dev, 44 tablas, 19 migraciones y 019 aplicada. El siguiente incremento de credenciales está documentado en CAM-095 y requiere sus propias comprobaciones. (José Aránguiz)
