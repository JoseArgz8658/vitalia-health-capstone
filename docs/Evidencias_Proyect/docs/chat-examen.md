# Fase 5.17 — Asistente de un examen y explicación ampliada

## Alcance
Versión 2 redacta explicaciones con conocimiento general del modelo, sin limitarse a cuatro definiciones del catálogo anterior. Chat y explicación están vinculados a una revisión aprobada inmutable de un documento propio stored. No hay acceso del asistente a otros documentos, S3, navegación web, herramientas ni historial clínico general. No se entregan observaciones, correo ni salida cruda OCR al modelo. La revisión contiene nombre/fecha/resultados y se envía únicamente a Ollama local.

La IA debe reconocer insuficiencia, rechazar temas externos y solicitudes de diagnóstico/receta/tratamiento/recomendaciones. Backend aplica filtros de entrada, esquema estricto, referencias a filas válidas, filtros conservadores de salida y ausencia de cifras/URLs inventadas en la prosa. Cifras y unidades visibles se copian directamente de la revisión. Indicadores ficticios conocidos (Alfa/Beta/etc.) se tratan como desconocidos; no se inventa su significado. La comparación entre documentos está pendiente de otra fase.

Estos filtros NO garantizan verdad médica, coherencia semántica ni ausencia absoluta de invenciones o recomendaciones. También pueden rechazar preguntas/respuestas benignas. Todo el contenido sigue approved:false y tiene aviso visible. Modelo general qwen3:4b-instruct, no modelo médico validado. Solo pruebas ficticias; no presentar esta versión como servicio clínico aprobado. El texto libre nuevo no tiene fuente bibliográfica verificada ni URLs generadas por el modelo.

## Datos y versiones
Migración 011 crea vitalia_exam_assistant_threads, vitalia_exam_assistant_turns y vitalia_exam_assistant_audit. Un hilo por revisión; snapshot, paciente y documento se fijan en el servidor. Turno con UUID, ordinal, pregunta, modo chat/explanation, status pending/ready/failed, intento UUID, respuesta validada y modelo/prompt versión 2. Auditoría de consultas, solicitudes, finalizaciones y fallos. Consulta paciente solo; otros roles 403, ajeno 404, sin sesión 401, entrada extra/límites 400, revisión ausente/conflicto/cupo 409 y ocupado/rechazo técnico 503. Cache-Control:no-store.

POST chat acepta únicamente {requestId,question}; no paciente, contexto, reviewId, modelo ni historial del cliente. GET obtiene hasta treinta turnos de ese documento. El modelo usa hasta seis respuestas educativas anteriores del mismo hilo; rechazos no se usan como contexto. Se recorta la memoria más antigua si revisión+memoria excede veinte mil bytes. Una pregunta tiene hasta quinientos caracteres; examen hasta veinte resultados y doce mil bytes. Límite de treinta solicitudes chat por revisión (incluye fallos/rechazos); no hay reinicio ni borrado de conversación en esta fase.

Idempotencia: repetir el mismo requestId con la misma pregunta devuelve su estado/respuesta sin generar otra. Cambiar pregunta con el mismo ID da conflicto. Fallo confirmado requiere nueva solicitud; si se perdió la respuesta, actualizar primero y reutilizar el ID. La UI conserva ese ID mientras no obtiene una respuesta definitiva. Un solo pending por hilo, serialización bajo bloqueo PostgreSQL y cupo por proceso. Timeout de modelo ciento veinte segundos y respuesta máxima sesenta y cuatro KiB; cliente espera ciento cincuenta segundos. POST posterior recupera pendientes de más de tres minutos marcándolos failed; el UUID del intento impide que una ejecución antigua publique después. La explicación fallida puede reintentarse pasados treinta segundos. No hay ejecución/reintento automático.

Las explicaciones de la versión 1 en la tabla 010 se conservan. La interfaz nueva consulta /assistant/explanation, con su propia persistencia, y no sobrescribe aprobaciones profesionales ni registros anteriores.

## API
- GET /api/documents/:id/assistant: estado e historial de chat.
- POST /api/documents/:id/assistant: requestId UUID y question.
- GET /api/documents/:id/assistant/explanation: explicación versión 2 guardada o estado.
- POST /api/documents/:id/assistant/explanation: cuerpo {} para solicitar explicación.

## Comprobación Windows
Detener backend y Flutter con Ctrl+C. Desde la raíz:

```powershell
git fetch origin
git switch --track origin/fase-5/chat-examen
cd backend
npm test
$LASTEXITCODE
```

Debe terminar con resumen completo y cero; la última ejecución compartida anteriormente terminaba en RUNS sin resumen, por lo que no se da por comprobada automáticamente.

```powershell
node --env-file=.env dist/database/migrate-exam-assistant.js
node --env-file=.env dist/database/verify-exam-assistant.js
$LASTEXITCODE
```

Verificador usa IA simulada y PostgreSQL real en transacción; revierte todos los datos ficticios. Comprueba persistencia, idempotencia, acceso propio, rechazo de otro examen y conservación del original. No llama a S3 ni Ollama. Requiere migración 010 previa.

Con Ollama abierto y qwen3:4b-instruct instalado:

```powershell
node dist/exam-assistant/evaluate.js
$LASTEXITCODE
```

Once casos ficticios: explicación, hemoglobina, creatinina (fuera del catálogo previo), unidad, referencia, seguimiento, indicador ficticio, tratamiento, otro examen, otro tema e instrucciones maliciosas. Puede tardar varios minutos; cada caso tiene límite de dos minutos. Muestra pass/expected, respuesta y latencia; código uno si hay fallos. Éxito automático evalúa estructura, tipo de respuesta y conservación de datos: NO certifica definiciones médicas correctas. Leer las respuestas educativas y compartir la salida para evaluar y ajustar. Modelo real, PostgreSQL y Flutter no están disponibles en el entorno de implementación.

Después:

```powershell
npm start
```

Otra terminal:

```powershell
cd C:\Users\josem\Documents\GitHub\vitalia-health-capstone-prueba\apps\vitalia
flutter pub get
flutter analyze
flutter test test/auth_api_test.dart test/acceso_integrado_test.dart test/documentos_api_test.dart test/paciente_documentos_test.dart test/procesamiento_test.dart test/asignaciones_test.dart test/profesional_test.dart test/revision_profesional_test.dart test/revision_paciente_test.dart test/explicacion_test.dart test/chat_examen_test.dart
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

Paciente => documento aprobado => Ver resultados revisados. Consultar/Generar explicación usa versión ampliada. Abrir conversación carga ese historial; enviar pregunta vinculada al examen. Con Indicador Alfa/Beta preguntar por su significado debe reconocer desconocimiento. Preguntar por su unidad o qué es un rango puede dar explicación general sin inventar significado de Alfa. Para comprobar conocimiento del modelo sobre indicadores reales usar la batería ficticia de evaluación o un documento ficticio con nombres médicos reales, nunca cambiar el significado de Alfa a una prueba médica sin fundamento.

Cambiar a otro documento debe mostrar otra conversación. Reabrir el mismo conserva mensajes. Consulta fallida/401 retira datos; el contenedor cierra la sesión al vencer. Las preguntas repetidas con nuevo ID cuentan como solicitudes nuevas. La UI es funcional; rediseño intuitivo queda pendiente expresamente.

## Ajuste educativo del prompt (revisión 2)
El contrato persistido continúa en versión 2; este ajuste del prompt no cambia el esquema de tablas ni reescribe respuestas guardadas. La evaluación muestra la revisión del prompt por separado. Se distingue definición general de interpretación individual y se permite explicar conceptos reconocibles aunque falten cifras o haya otra fila desconocida. No se convierten automáticamente rechazos en respuestas educativas.

La evaluación aislada informa `reason` en los fallos: `http`, `transport`, `timeout`, `response_limit`, `invalid_json`, `incomplete`, `invalid_reply`, `invalid_references`, `unsafe_content`, `chat_format`, `partial_explanation` o `invalid_definition`; configuración/entrada inválida tienen motivos propios. No imprime contenido rechazado, errores internos ni credenciales. Un mensaje `insufficient` válido sigue apareciendo como respuesta y se compara con el objetivo del caso. Los filtros conservadores permanecen y pueden rechazar respuestas educativas legítimas: el motivo sirve para investigarlas.

Esta evaluación necesita Ollama, no PostgreSQL. Ejecútala desde backend: `node dist/exam-assistant/evaluate.js`. Si Ollama ya ocupa el puerto, no inicies una segunda instancia. Las respuestas anteriores listas siguen reutilizándose; el ajuste no regenera conversaciones ni explicaciones existentes.

## Prompt revisión 3
El esquema de generación depende del modo: definitions vacío en chat y una entrada por fila en explicación. El encabezado de explicación debe evitar repetir definiciones. La evaluación E01 exige identificar hemoglobina, plaquetas y creatinina, conservando desconocido el indicador ficticio. Los fallos unsafe_content siguen rechazados: un ejemplo más preciso de rango no modifica el filtro.

## Prompt revisión 6 y reformulación
Se permite una reformulación tras rechazo de contenido, sin reenviar la prosa rechazada. Las dos solicitudes comparten un máximo total de 120 segundos; se informa generationAttempts en evaluación. El filtro permanece sin cambios. El seguimiento debe explicar finalidad si esa es la pregunta, y la batería adicional incorpora un criterio heurístico para ello. Una respuesta libre puede seguir siendo imprecisa pese a superar estos controles.

## Definiciones y finalidad estables (revisión 7)
Las cinco notas verificadas aportan las definiciones de sus filas en explicación, y la finalidad cuando se pregunta por una sola medición cubierta. No dependen de que el modelo declare known=true. La respuesta libre de otros conceptos conserva su incertidumbre y no recibe una cita por coincidir solo el nombre. La evaluación expone verifiedNoteIndices; estos metadatos de diagnóstico no se guardan como columnas nuevas. La explicación muestra source solo si su definición coincide exactamente con la nota verificada. Las fuentes no equivalen a aprobación profesional. Las respuestas listas anteriores no se regeneran.
