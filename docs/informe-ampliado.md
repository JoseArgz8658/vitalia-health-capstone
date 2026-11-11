# Probar el informe ampliado

Seleccionar `fase-5/informe-completo`, actualizar y detener API/worker anteriores. En backend:

```powershell
npm test
npm start
```

En otra terminal backend:

```powershell
npm run worker
```

No hay migración nueva. En apps/vitalia:

```powershell
flutter analyze
flutter test
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

Subir un documento ficticio nuevo y solicitar procesamiento. No repetir ni modificar un documento ya aprobado. El profesional compara los datos de paciente y estudio, fechas separadas, resultados y estados escritos con el original, corrige con motivo y confirma. La cuenta que sube el documento no aporta su nombre a la extracción.

El paciente abre la nueva revisión y puede preguntar «¿Cuál es el nombre completo?», «¿Quién solicitó el examen?», «¿Cuál es la fecha de toma de muestra?» y «¿Cuál es la fecha de emisión?». Datos ausentes se declaran ausentes. Un informe puede contener observaciones médicas: se conservan como texto del documento, no como conclusiones nuevas del asistente.

La explicación de hasta veinte indicadores se genera completa por bloques pequeños, con un límite total de dos minutos. Si falla, no entrega un fragmento como si fuera completo. Revisar el mensaje y `exam_assistant_failure` sin compartir contenido clínico ni secretos. Definiciones sin fuente verificada siguen siendo contenido generado que puede contener errores.
