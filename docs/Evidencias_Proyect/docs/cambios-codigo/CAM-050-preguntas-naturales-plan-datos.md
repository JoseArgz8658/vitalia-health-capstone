# CAM-050: aclaraciones del chat y planificación del modelo de datos

Autorización: continuar donde se quedó, preguntas naturales y diseño de datos solicitado el 7 de octubre de 2026.

Se incorporan respuestas deterministas de aclaración para quién realizó el examen y fecha de carga, sin llamar a Ollama ni confundir solicitante, validante o laboratorio. Fecha de carga todavía no forma parte del contexto del asistente; se informa esa limitación sin sustituirla por emisión. Se reconocen algunas variantes de quién pidió el examen. Las restricciones de diagnóstico y solicitudes maliciosas siguen evaluándose antes de estas respuestas. Solo se aceptan textos finitos exactos; no se permite añadir recomendaciones.

Los rechazos del asistente ahora incluyen una categoría acotada: numeric_text, external_link, classification_term o clinical_or_instruction_term. Se mantiene la exclusión de preguntas, documentos, respuestas, identidades y mensajes de excepción. Esto permite diagnosticar las explicaciones rechazadas en el equipo del usuario; todavía no resuelve ni demuestra la causa semántica exacta. No se amplía el catálogo médico ni se debilitan validaciones.

Se documenta el inventario de 17 tablas actuales y un plan de modelado anterior a la fase multiclínica en docs/modelo-datos/00-alcance-y-plan.md. Entidades y atributos futuros son candidatos, no DDL implementado. No cambia PostgreSQL, no requiere migración ni crea clínicas, provincias o comunas.

Pruebas: preguntas ambiguas, fecha de carga distinta de emisión, respuestas finitas sin red y registro seguro de categoría. Reversión: volver a 428b6bfd8e1adb50b215f0dd7758c4213ce86727. Originales y revisiones existentes se conservan.

Resultado local: compilación TypeScript y 85 pruebas aprobadas en exam-assistant y report-extraction. No hay cambios de Flutter en este ajuste. La explicación educativa sigue pendiente de diagnóstico real con la nueva categoría; no se afirma resuelta.
