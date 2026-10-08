# CAM-054 — Definiciones verificadas para indicadores habituales

## Motivo y alcance autorizado
Continuación solicitada tras comprobar cobertura insuficiente por timeout de bloques. Se amplía el catálogo educativo a los dieciséis conceptos del informe de prueba, con alias exactos, fuente MedlinePlus y finalidad de medición. No se comparan valores ni se diagnostica o recomienda tratamiento. Conocimiento versión 2.

Se reconocen nombres compuestos como Glóbulos Blancos (Leucocitos), Glucosa en Ayunas, VCM (Volumen Corpuscular Medio), TGP (ALT) y TGO (AST). Urea y nitrógeno ureico no se equiparan. No se usan coincidencias parciales que conviertan nombres desconocidos en conocidos.

La explicación larga de estos dieciséis conceptos se resuelve con las notas verificadas, sin generación de Ollama. Conceptos ajenos al catálogo conservan validaciones, bloque acotado e incertidumbre explícita. No equivale a conocimiento médico completo.

## Consulta de explicación previamente guardada
La vista aplica las definiciones actuales a las filas correspondientes de la copia revisada. No altera la respuesta histórica almacenada, datos originales, revisión, fechas ni autorías. Cada definición proveniente del catálogo muestra su fuente. Consultar explicación recupera también esta cobertura actualizada sin repetir generación.

## Fuentes revisadas
MedlinePlus en español: conteo de glóbulos rojos, hematocrito, prueba de sangre de VCM, colesterol, HDL, LDL, triglicéridos, prueba de AST, panel metabólico completo, bilirrubina y ciclo de la urea. URLs exactas por concepto en knowledge.ts. Definiciones breves redactadas a partir de las fuentes, sin copiar consejos ni clasificaciones de resultados.

## Pruebas
121 pruebas focalizadas pasaron. Casos nuevos verifican cobertura completa del informe de dieciséis indicadores sin petición al modelo y actualización de la vista de una explicación antigua sin modificar respuesta ni cifras. Comprobación manual con el equipo del usuario pendiente.

## Reversión
Restaurar knowledge.ts, contract.ts y report-extraction.test.cjs al commit 146b4bfa. No hay migraciones ni dependencias nuevas.
