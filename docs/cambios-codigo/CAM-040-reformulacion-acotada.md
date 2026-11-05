# CAM-040 — Reformulación educativa acotada

Dentro de la continuación autorizada. Batería principal 11/11 y adicional 5/6; creatinina rechazada por términos clínicos/instrucciones, y seguimiento aprobado estructuralmente pero sin explicar finalidad.

Prompt revisión 6: responder finalidad desde notas purpose cuando se pregunta para qué se mide, y no discutir diagnósticos ante definiciones generales. Se elimina de la nota de creatinina una negación sobre enfermedades que no era necesaria para explicar finalidad.

Si una respuesta incumple el filtro de contenido, se permite una única segunda generación. No se reenvía la prosa rechazada. La segunda respuesta se valida íntegramente; dos rechazos producen error. Sin reintentos ante fallos HTTP, transporte, referencias o formato. Ambas generaciones comparten presupuesto total de 120 segundos; la evaluación informa generationAttempts. No se altera el historial ni se entrega contenido parcial.

La evaluación adicional exige que el seguimiento mencione medición/cantidad; es un control heurístico, no verificación semántica. Tests para éxito al reformular, doble rechazo y HTTP sin reintento. Compilación y 61 pruebas del asistente aprobadas, incluido límite temporal compartido. Modelo real pendiente. Sin migración ni dependencias. Reversión: restaurar los archivos anteriores y compilar.
