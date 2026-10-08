# CAM-066 — Espera y seguimiento del chat

Durante el envío se muestra la pregunta enviada y una tarjeta de espera junto al final de la conversación. La carga inicial tiene un mensaje diferente al de generación. En la pantalla dedicada, enviar cierra el teclado y desplaza hacia el campo al iniciar y terminar la solicitud para acercar la respuesta nueva. Los errores se anuncian con Semantics liveRegion.

No se repiten solicitudes automáticamente ni se modifican contexto, idempotencia, límites o respuestas del backend. El desplazamiento automático solo se activa en el modo autoOpen de la pantalla de chat.

Flutter no está instalado aquí: ejecutar flutter analyze y flutter test. Comprobar conversación larga, teclado móvil, pregunta rechazada y vuelta a resultados. La espera representa actividad, no porcentaje de progreso.
