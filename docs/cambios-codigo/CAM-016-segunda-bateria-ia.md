# CAM-016 — Prompt versión 3 y segunda batería

## Autorización
El usuario autorizó ajustar el prompt y crear una segunda batería independiente el 1 de octubre de 2026.

## Cambios
Prompt con independencia de campos y reglas explícitas del calendario. Valor ilegible no invalida unidad o rango visibles. Diez textos nuevos en casos-extraccion-independientes.json, dos pruebas en casos-independientes.test.mjs y opción --independiente en el evaluador. Los informes identifican batería y prompt versión 3. Guía actualizada.

## Evidencia y verificación
Versión 2 comunicada por el usuario: 6/8, con fallos en rango visible de plaquetas y fecha imposible; duraciones 528–2768 ms. La versión 3 está pendiente contra el modelo real.

Comprobación de sintaxis y ocho pruebas automatizadas aprobadas (seis existentes y dos nuevas). Ollama no está disponible aquí. Casos originales, resultados esperados y criterios permanecen iguales.

## Límites
Los textos nuevos no se incorporan a los ejemplos del prompt. Cubren errores conocidos y no son una evaluación externa. Si se ajusta el prompt según la segunda batería, también pasa a ser de desarrollo. No se acredita uso clínico ni integración.

## Reversión
Restaurar evaluador y guía a la versión anterior; eliminar casos y pruebas nuevos. Sin cambios de backend, Flutter o base de datos.
