# CAM-039 — Alias y seguimiento del asistente

Corrección dentro de la continuación autorizada, después de la batería principal 11/11 y adicional 2/6.

El filtro inicial reutiliza selección de filas para reconocer alias como Hb únicamente cuando corresponde al examen abierto. Indicadores ficticios con nombres de letras griegas, incluido Analito Omega, se rechazan por política antes del modelo. El esquema de generación restringe índices a las filas objetivo y aporta su índice real, conservando el rechazo backend ante referencias ajenas. Prompt revisión 5; contrato persistido 2.

Pruebas de regresión para alias ausente/presente y seguimiento tras cambiar el orden de filas. No se relajan filtros ni se altera el criterio de evaluación. La respuesta rechazada por unsafe_content permanece rechazada; la evaluación ahora informa categoría acotada (cifras, enlace, clasificación o términos clínicos/instrucciones), sin imprimir prosa rechazada. Sin migración ni dependencias nuevas. Reversión: restaurar archivos anteriores y compilar.
