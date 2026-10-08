# CAM-067 — Acceso flotante a la IA desde resultados

La pantalla de resultados incluye un FloatingActionButton.extended con icono y texto Preguntar a la IA, manteniendo el acceso al final del contenido. Ambos usan la misma navegación y copia revisada del examen. El botón aparece únicamente cuando se obtuvo y validó una revisión aprobada; se retira al actualizar, ante error o ausencia de revisión. Se reserva espacio inferior de desplazamiento para evitar tapar el último contenido.

No se generan respuestas al consultar resultados ni se modifican permisos o datos del backend. El notificador de la ruta se libera al cerrar y las consultas comprueban mounted antes de comunicar resultados.

Flutter no está disponible aquí. Ejecutar flutter analyze y flutter test; verificar botón flotante, acceso inferior, volver del chat y examen sin revisión, en web y móvil.
