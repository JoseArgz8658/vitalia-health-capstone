# CAM-017 — Informar discrepancias pese a errores de validación

## Autorización
El usuario autorizó el ajuste tras comparar ambos modelos el 1 de octubre de 2026.

## Cambio
assess acumula validate y compare sin detenerse por una fecha inválida. No modifica la respuesta ni los resultados esperados. Los campos faltantes solo se derivan cuando la validación es correcta; en otro caso se informa null. El caso aprueba únicamente sin errores.

Se agregan dos pruebas: fecha inválida junto con cambios de valor/unidad y respuestas de estructura inválida. Se registra comparación en docs/avance/fase-5-02-comparacion-modelos.md.

## Verificación
Diez pruebas automatizadas aprobadas. Los casos inválidos siguen fallando y los exactos siguen aprobando. Ejecución contra Ollama pendiente en Windows. No cambia prompt, parámetros, baterías ni código de Vitalia.

## Reversión
Restaurar evaluador y pruebas al commit anterior; eliminar el nuevo avance. Sin migraciones o cambios de datos.
