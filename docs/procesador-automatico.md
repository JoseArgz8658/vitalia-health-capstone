# Procesador automático

En el entorno local existente: desde backend, npm run build y npm run worker. Mantener API y Ollama activos. Solicitar extracción desde la aplicación y actualizar el estado; no ejecutar process-document --apply con worker activo. Ctrl+C espera el trabajo activo y cierra el proceso.

El worker procesa solicitudes compatibles queued de una en una. Utiliza un bloqueo exclusivo compartido con la herramienta manual. Al arrancar recupera trabajos processing huérfanos como failed/processing_interrupted; no se reenvían automáticamente ni se pierde el original. Si la conexión del bloqueo se pierde, termina. Los estados finales y aprobaciones profesionales permanecen sin cambios.

La guía README cubre Docker y otros equipos. Para la instalación actual no hay que reemplazar .env ni mover PostgreSQL/S3 a Docker para probar este worker.
