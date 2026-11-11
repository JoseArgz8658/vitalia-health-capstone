# CAM-038 — Fundamento y referencias del asistente

## Autorización
El usuario pidió continuar hasta completar las fases pendientes, tras evaluar coherencia y precisión del asistente.

## Implementación
Nuevo knowledge.ts con notas generales verificadas de hemoglobina, plaquetas, creatinina, leucocitos y glucosa. Solo se envían notas correspondientes al examen abierto. Coincidencia por nombres y alias exactos; no consulta web con datos del paciente. No se reescribe la extracción ni la revisión.

El prompt revisión 4 recibe evidencia y filas objetivo para preguntas explícitas, unidades y seguimiento. Una respuesta educativa que enlaza filas ajenas al objetivo se rechaza. Se conservan filtros, incertidumbre, contexto y formato. Esto no demuestra que una respuesta libre respete todas las fuentes. Fuera de las notas, el conocimiento del modelo no queda verificado.

Evaluación existente comprueba referencias esperadas. Nueva batería de seis casos adicionales: orden distinto, alias, valores ausentes, conceptos adicionales, seguimiento y desconocido. No certifican veracidad médica.

## Fuentes revisadas
MedlinePlus, consulta 07-10-2026 UTC: hemoglobina (ency/article/003645.htm), creatinina en orina (ency/article/003610.htm), conteo sanguíneo completo, conteo de glóbulos blancos y bloodglucose.html. URLs completas en knowledge.ts. Notas redactadas como paráfrasis educativas, sin interpretar resultados ni recomendar acciones.

## Validación y reversión
54 pruebas del asistente y compilación; batería completa de 358 pruebas en 35 suites aprobada. Modelo real requiere evaluación en Windows. Sin migración ni dependencias nuevas; respuestas previas no se regeneran. Restaurar archivos desde el commit anterior para revertir.
