# CAM-052: explicación con cobertura limitada explícita

Autorización: continuar donde se quedó tras comprobar el chat, el 7 de octubre de 2026.

En explicaciones largas procesadas por bloques, dos rechazos de contenido en un bloque ya no eliminan las definiciones verificadas o aceptadas de otros bloques. Las filas de ese bloque reciben una respuesta fija sin explicación y known=false. No se conserva ni presenta contenido rechazado. La validación completa sigue aplicada al resultado ensamblado. No se debilitan los filtros ni se agregan definiciones médicas sin fuentes. La cobertura puede ser parcial y no se considera aprobación profesional.

Solo se trata así unsafe_content después de la única reformulación. HTTP, transporte, tiempo excedido, estructura y referencias inválidas siguen deteniendo la operación. El límite global permanece en dos minutos. Explicaciones cortas y chat conservan su política actual de fallo. Contrato persistido 2; revisión textual del asistente 9.

La pantalla de explicación muestra actividad indeterminada y señala cuando hay indicadores sin explicación, aclarando que eso no implica datos de examen incorrectos. No se modifica una explicación ready ya guardada ni una revisión profesional.

Verificación: TypeScript y 118 pruebas en report-extraction, exam-assistant y explanations aprobadas. Prueba nueva comprueba que dos respuestas rechazadas no se muestran, las definiciones previas siguen disponibles y el bloque siguiente se valida. Los tests anteriores de fallos HTTP y presupuesto compartido continúan pasando. Flutter y Ollama reales pendientes en el equipo del usuario.

Sin migraciones ni dependencias nuevas. Reversión: volver al commit 911b0347bc579dbc71463c7f30167a98ec55bf95.
