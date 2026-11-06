# CAM-058 — Inicio e historial del paciente

Continuación autorizada de fase visual. Encabezado con marca, orientación y cuenta; subir examen destacado; historial con título, estado vacío y carga. Tarjetas separadas con nombre, metadatos y archivo original distinguidos del bloque de procesamiento. Estado usa icono y texto: color no es único indicador.

El indicador de espera refleja la consulta o el estado registrado queued/processing. No afirma porcentaje ni actualización automática: indica actualizar estado. Estado revisado conserva únicamente el valor informado por API. No cambian consultas, permisos, descargas ni solicitudes.

Prueba de paciente desplaza hasta botones antes de pulsar, evitando depender de ubicación fija tras ampliar encabezado. Mantiene comprobaciones de carga, historial y logout.

Verificación Flutter pendiente en equipo usuario (analyze, test y revisión web/móvil); Flutter no disponible aquí. Revisar nombres largos y pantallas estrechas.

Reversión: restaurar paciente_documentos_page.dart, procesamiento_panel.dart y paciente_documentos_test.dart al commit d53b334f. Sin migraciones ni dependencias.
