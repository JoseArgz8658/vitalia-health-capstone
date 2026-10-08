# Fase 5.02 — Comparación local de modelos

Resultados comunicados por el usuario el 1 de octubre de 2026, con prompt versión 3 y los mismos parámetros y criterios:

| Modelo | Desarrollo | Segunda batería |
| --- | --- | --- |
| qwen2.5:3b | 6/8 | 6/10 |
| qwen3:4b-instruct | 7/8 | 7/10 |

Qwen3 recuperó el rango omitido en el caso 02 y el título del caso I10. Persistieron fechas imposibles (04, I02, I04) y unidad omitida (I01). El evaluador anterior detenía la comparación de campos tras detectar validación inválida; los tres casos de fecha podían contener más discrepancias no informadas.

Se ajusta el evaluador para acumular errores de validación y diferencias frente a la referencia incluso con fecha inválida. La respuesta original no cambia y el caso sigue fallando. Diez pruebas del evaluador aprobadas; reevaluación real pendiente.

Tiempos de Qwen3 comunicados: desarrollo 1761–13678 ms, segunda batería 1405–6738 ms. La primera medición puede incluir carga, pero no se confirmó su causa. No son mediciones controladas de rendimiento.

Ningún modelo se aprueba aún para integración. La segunda batería ya se conoce; futuras decisiones deben considerar esta exposición. Los casos de instrucciones incrustadas aprobados no acreditan resistencia general.
