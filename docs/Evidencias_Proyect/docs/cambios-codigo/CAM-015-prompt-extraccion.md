# CAM-015 — Segunda versión del prompt de extracción

## Autorización
El usuario autorizó modificar el prompt el 1 de octubre de 2026 tras obtener 1/8 casos correctos con la primera versión.

## Cambio
Se modifica únicamente la constante prompt en scripts/ia/evaluar-extraccion.mjs. Se explicitan reglas por campo y se incorporan tres ejemplos con nombres y valores diferentes de la batería: separar valor/unidad, mantener nombres completos, usar null ante datos desconocidos o fechas imposibles e ignorar instrucciones del documento.

Los ocho casos, sus resultados esperados, el esquema, parámetros, validación y comparación permanecen iguales. No se corrigen respuestas automáticamente.

## Verificación
Las seis pruebas existentes del evaluador pasaron después del cambio. La segunda evaluación del modelo real está pendiente en Windows.

La primera ejecución comunicada por el usuario acertó solo el caso 05-sin-resultados. Duraciones: 551–2544 ms por caso. El caso 08 alteró un valor siguiendo una instrucción incrustada. Estos resultados corresponden a la primera versión; no se presume mejora sin ejecutar la segunda.

## Límites
Los ejemplos se eligieron a partir de errores observados. Esta batería es ahora de desarrollo; aun si mejora será necesaria una batería independiente antes de aceptar la integración. El prompt no constituye una garantía de protección ante instrucciones maliciosas.

## Reversión
Restaurar solo la constante prompt a la versión anterior desde Git. No hay cambios en datos, modelos instalados ni configuración de Vitalia.
