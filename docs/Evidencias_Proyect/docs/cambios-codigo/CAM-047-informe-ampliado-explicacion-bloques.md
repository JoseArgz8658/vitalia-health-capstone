# CAM-047 — Informe ampliado y explicación por bloques

Autorización explícita del usuario: extracción de paciente, estudio, resultados y validación del informe; persistencia, revisión y chat, más ajuste de explicación.

## Datos y compatibilidad

`informe` incorpora nombre del paciente, edad, sexo, nacimiento, expediente, solicitante, fecha/hora de muestra y emisión, laboratorio, observaciones originales, validante y registro profesional. Cada dato desconocido es null; las fechas normalizadas deben existir. Cada resultado puede conservar `estado_documento`, etiqueta literal sin cálculo clínico.

Versiones: las solicitudes nuevas de la aplicación y el comando manual usan prompt 4, con informe requerido. Los trabajos anteriores de prompt 3 conservan su prompt y siguen procesables. La función de reserva interna mantiene 3 por defecto para verificadores antiguos; el servicio de aplicación pide 4 explícitamente.

PostgreSQL ya conserva resultado, extracción original, revisión y contexto como JSONB. No hay migración SQL ni relleno retrospectivo. Revisiones aprobadas permanecen inmutables; para probar datos nuevos se necesita un documento ficticio nuevo. El esquema no usa valores por defecto que alteren el snapshot de revisiones antiguas.

## Revisión y consultas

Flutter permite corregir todos los campos nuevos antes de confirmar. Presenta paciente/estudio separados de observaciones del profesional y conserva estado literal. El backend rechaza fechas imposibles del informe y la eliminación silenciosa del bloque informe durante revisión. Las correcciones siguen exigiendo observación. Cuenta del paciente, profesional que revisa y médicos escritos en el informe son identidades distintas.

El asistente copia campos confirmados del informe y valores/unidades/referencias/estado de una fila inequívoca, sin Ollama. Las respuestas factuales pasan una comparación exacta con un texto construido desde la revisión. No se acepta texto adicional ni cifras ajenas. No calcula edad ni interpreta etiquetas.

## Explicación

Para más de cuatro indicadores, usa definiciones verificadas ya existentes y procesa los restantes por bloques de hasta tres. Remapea índices a su fila original y valida la explicación completa. Todos los bloques y reformulaciones comparten el límite total de 120 segundos. Un bloque fallido no entrega ni guarda explicación parcial. No aumenta el límite ni garantiza rendimiento en cualquier equipo; máximo actual de 20 indicadores por explicación.

Los datos personales de informe no se envían al modelo educativo. La memoria de turnos sin filas (consultas del informe) se excluye de la generación. El documento completo se usa solo para extracción local.

## Verificación y reversión

Pruebas: versión 4 y compatibilidad 3, fechas, datos confirmados, transcripción literal de estados, corrección/persistencia e inmutabilidad, bloques/remapeo, privacidad, fallo sin parcial y límite total; pruebas Flutter de campos y revisión añadidas. Flutter/Ollama/PostgreSQL reales se verifican en Windows por el usuario.

Revertir este commit devuelve código anterior, que no interpreta informes v4. Antes de revertir, detener el worker; conservar originales y revisiones. No borrar JSONB ni modificar migraciones previas.
