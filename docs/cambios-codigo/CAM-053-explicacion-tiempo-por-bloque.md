# CAM-053 — Explicación con tiempo acotado por bloque

Autorizado al continuar la corrección de consultar/generar explicación.

## Problema y cambio
Dos intentos reales finalizaron por timeout a los 120 segundos. La explicación larga perdía también las definiciones verificadas cuando un bloque lento agotaba el presupuesto global.

Las explicaciones de más de cuatro indicadores conservan las notas verificadas y limitan cada bloque de hasta tres conceptos pendientes a diez segundos, compartidos con su posible reformulación. Si se agota ese tiempo, sus filas quedan sin explicación disponible con un aviso explícito. Las siguientes filas continúan. Esto entrega cobertura educativa parcial; no asegura que todos los conceptos tengan explicación ni mejora la velocidad del modelo.

El límite global sigue siendo dos minutos. Las explicaciones cortas y el chat conservan su comportamiento. HTTP, transporte, estructura y referencias inválidas siguen fallando; el control de contenido no se relaja. No cambia PostgreSQL ni la extracción original ni la revisión profesional.

## Verificación
Pruebas focalizadas de extracción de informe, asistente y explicaciones. Casos de tiempo simulado verifican abortar bloques, conservar notas verificadas y continuar con bloques posteriores. Falta comprobar con Ollama en el equipo del usuario.

## Reversión
Restaurar local-model.ts, contract.ts y report-extraction.test.cjs al commit anterior 8f763cb. No requiere migraciones.
