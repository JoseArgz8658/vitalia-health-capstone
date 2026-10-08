# CAM-063 — Consulta profesional en vista dedicada

El usuario observó que el resultado quedaba al final del historial. La selección ahora cambia a una vista dedicada del examen dentro de la pantalla profesional, sin duplicar consulta ni procesar de nuevo. Se muestra al inicio con nombre, paciente, actualizar extracción, descargar original y volver. Historial deja de renderizarse mientras está abierta.

Volver o Cerrar consulta conserva la lista/página y cancela polling. Atrás de Android cierra consulta mediante PopScope cuando no hay operación pendiente; guardado bloquea salida como antes. Temporizador de actualización y clave de revisión por estado se conservan.

Flutter no disponible aquí: ejecutar analyze, test y probar consulta, descarga, actualización y retorno web/Android. No se afirma prueba ejecutada.

Reversión: restaurar profesional_documentos_page.dart al commit anterior. Sin migraciones ni dependencias.
