# CAM-051: preguntas de seguimiento y conversación ante rechazo

Autorización: corrección de los fallos reportados al continuar las consultas del asistente (7 de octubre de 2026).

Se reconoce «y el profesional que me validó el informe» como campo profesional_validante y «y sobre el laboratorio que lo hizo» como laboratorio. Son respuestas deterministas de datos revisados, sin generación de Ollama. Si laboratorio no figura en la revisión se informa ausencia; no se deduce de los médicos. Las reglas previas de restricción y la validación exacta de respuestas se conservan.

Un HTTP 503 del asistente deja visible el historial validado y consulta el estado de los turnos automáticamente. No repite el POST ni la generación. Si se confirma un turno fallido, libera su identificador para una nueva solicitud manual. Si no puede confirmarse por conexión, conserva el identificador evitando duplicar la misma solicitud. Una respuesta malformada no se presenta; se exige refrescar antes de continuar, conservando el historial anterior.

Actualizar conversación no borra preventivamente el historial durante la espera. Sesión expirada o acceso revocado (401/403/404) sí retiran los datos y el formulario. Si la consulta devuelve not_available también los retira. Durante consulta o envío aparece una barra indeterminada. Esto no constituye el rediseño visual completo del chat.

Pruebas backend: seguimientos, laboratorio ausente y validación sin modelo. Pruebas Flutter añadidas: rechazo no cierra conversación ni reenvía, nueva pregunta manual y revocación durante recuperación. Flutter no está disponible localmente; verificar en Windows. No hay migración ni nuevas dependencias. La explicación educativa continúa pendiente de su diagnóstico real; estos registros invalid_references corresponden al chat.

Reversión: volver al commit fb355557d712233a6abd7d767adb456ee3527648. No modifica revisiones ni originales.

Comprobación local: TypeScript compila y las 89 pruebas de report-extraction y exam-assistant pasan. Flutter queda pendiente de ejecución en Windows. Al confirmar un turno fallido, el aviso permite reformular y no obliga a actualizar manualmente una conversación ya verificada.
