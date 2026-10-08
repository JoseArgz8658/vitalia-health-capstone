# CAM-064 — Resultados del paciente en pantalla propia

## Problema y cambio
El historial desplegaba toda la revisión y explicación dentro de la tarjeta del examen. Ver resultados revisados ahora abre una ruta dedicada, consulta la revisión automáticamente y muestra un indicador de carga. El paciente puede volver mediante la navegación normal y abrir el chat desde la revisión aprobada.

## Conservación del flujo
Se reutilizan validaciones, consulta autenticada y manejo de errores existentes. No se genera IA al abrir resultados ni se cambia la aprobación profesional. El panel conserva su modo integrado por defecto para otros usos y pruebas. La caducidad de sesión retorna a la primera ruta antes del cierre de sesión.

## Validación pendiente
Flutter no está disponible en este entorno. Ejecutar flutter analyze y flutter test; comprobar paciente con revisión disponible, sin revisión, error y regreso desde chat/resultados en web y Android.
