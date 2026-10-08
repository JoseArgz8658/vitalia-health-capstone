# Fase 5.16 — Explicación educativa con asistencia de IA

## Alcance real de esta versión
No es un chatbot ni un intérprete clínico. Ollama clasifica nombres de indicadores de una revisión profesional aprobada en un catálogo cerrado; el backend valida el concepto contra alias exactos y presenta una definición general en español previamente documentada. No se publica texto libre del modelo. No se clasifica el valor como alto/bajo/normal, no se comparan rangos ni se deduce una enfermedad. Las cifras, fechas, unidades, referencias y ausencias se conservan desde la revisión, no desde la salida del modelo.

Catálogo inicial: Hemoglobina (Hb/Hgb), Plaquetas (Recuento de plaquetas), Leucocitos (Glóbulos blancos/Recuento de leucocitos) y Glucosa (Glucosa en sangre/Glucemia). Nombre no reconocido o ficticio => desconocido, con mensaje explícito de información insuficiente. Hemoglobina A1c no se confunde con hemoglobina. Alias exactos, sin coincidencias parciales. Hasta veinte indicadores y doce mil bytes de nombres por examen. Ampliar catálogo o generar narrativa libre requiere una evaluación posterior; no está cubierto aquí.

### Fuentes del catálogo
Definiciones generales parafraseadas y verificadas el 06-10-2026; sin trasladar rangos, recomendaciones ni criterios diagnósticos:
- MedlinePlus, Conteo sanguíneo completo: https://medlineplus.gov/spanish/pruebas-de-laboratorio/conteo-sanguineo-completo/
- MedlinePlus, Conteo de glóbulos blancos: https://medlineplus.gov/spanish/pruebas-de-laboratorio/conteo-de-globulos-blancos/
- MedlinePlus, Glucosa en sangre: https://medlineplus.gov/spanish/bloodglucose.html

Estos contenidos educativos no equivalen a validación clínica del producto. El modelo puede devolver desconocido aunque haya un concepto disponible; eso se acepta conservadoramente. Un concepto incompatible, texto libre, campos extra, filas reordenadas, respuesta truncada o incompleta se rechazan por completo. No se publica una respuesta parcial.

## Persistencia y permisos
Migración 010: vitalia_exam_explanations y vitalia_explanation_audit. Una explicación por revisión (review_id único), copia de datos revisados, status generating/ready/failed, intento UUID, modelo, prompt versión 1, catálogo versión 1 y tiempo. approved siempre false: la revisión aprueba los datos; no aprueba la explicación.

GET /api/documents/:id/explanation consulta y audita, sin IA. POST en la misma ruta, cuerpo vacío {}, genera explícitamente si existe revisión aprobada y documento propio stored. Cliente no decide paciente, revisión, modelo ni texto. Otros roles 403, sesión ausente 401, documento ajeno 404, sin revisión 409, entrada/límites 400, ocupado/generación fallida 503. Cache-Control:no-store. API pública sin prompt, claves S3, salida cruda del modelo ni identidad del profesional.

Modelo fijo qwen3:4b-instruct, http://127.0.0.1:11434/api/chat, sin redirecciones ni streaming. Solo recibe índices y nombres; nunca correo, observaciones, valor, unidad, fecha o documento. Timeout 120 segundos, respuesta máxima 64 KiB, límites estructurales. Se valida cada concepto en el backend, además del esquema de Ollama.

Una generación por proceso. La reserva PostgreSQL evita duplicados entre instancias; no hay transacción larga mientras trabaja Ollama. ready se reutiliza sin IA. failed requiere treinta segundos para reintentar; generating puede recuperarse por solicitud explícita pasados tres minutos. El UUID del intento evita que una ejecución anterior publique sobre otra. No hay worker automático en esta fase. No actualizar solo para regenerar: GET nunca ejecuta IA. Los resultados ready y las revisiones no se sobrescriben por la API.

## Pasos Windows
Detener backend y Flutter con Ctrl+C. Desde la raíz:

```powershell
git fetch origin
git switch --track origin/fase-5/explicacion-examen
cd backend
npm test
node --env-file=.env dist/database/migrate-exam-explanations.js
node --env-file=.env dist/database/verify-exam-explanations.js
$LASTEXITCODE
```

Verificador sin IA real: cuentas, revisión y explicación ficticias en transacción, revertidas al terminar. Sin S3. Debe decir: Explicaciones, revisión previa, persistencia, aislamiento y conservación del original correctos. Datos sintéticos revertidos.

Confirmar Ollama:

```powershell
ollama list
node dist/explanations/check.js
$LASTEXITCODE
```

Ollama debe estar abierto y el modelo qwen3:4b-instruct instalado (ya usado en la extracción). Si no está iniciado, abrir otra terminal con ollama serve y dejarla abierta; no iniciar un segundo servidor si el puerto ya está ocupado. El check usa datos ficticios, muestra definiciones permitidas o desconocido y no guarda nada en PostgreSQL/S3. Puede tardar hasta dos minutos. No se aceptan respuestas truncadas ni libres.

Luego, en backend:

```powershell
npm start
```

Otra terminal:

```powershell
cd C:\Users\josem\Documents\GitHub\vitalia-health-capstone-prueba\apps\vitalia
flutter pub get
flutter analyze
flutter test test/auth_api_test.dart test/acceso_integrado_test.dart test/documentos_api_test.dart test/paciente_documentos_test.dart test/procesamiento_test.dart test/asignaciones_test.dart test/profesional_test.dart test/revision_profesional_test.dart test/revision_paciente_test.dart test/explicacion_test.dart
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

Paciente => documento ficticio aprobado => Ver resultados revisados => Consultar explicación => Generar explicación. Repetir Consultar explicación debe devolver la misma explicación guardada sin generar otra. En Indicador Alfa/Beta corresponde desconocido, no una definición médica inventada. Verificar que se distingue el aviso de explicación no aprobada del estado de revisión de datos aprobados.

## Pendientes
Flutter y PostgreSQL externos requieren comprobación local del usuario. Modelo real requiere check en su equipo: mocks no prueban calidad ni velocidad de Ollama. Chatbot del examen en fase siguiente; evaluación ampliada de IA y rediseño visual pendientes. El catálogo es limitado y no resuelve por sí solo la propuesta completa de análisis asistido.
