# CAM-060 — Conversación en pantalla propia

Continuación autorizada tras validar interfaz de resultados. Botón Preguntar a la IA con icono abre ruta propia, muestra examen y ámbito, consulta conversación al entrar. Burbujas derecha paciente/izquierda IA, referencias y avisos conservados. Preguntas sugeridas rellenan campo; no generan respuestas automáticamente. Animación existente indica espera; no promete respuesta inmediata.

Mantiene validación de referencias, sesión, idempotencia y recuperación sin repetir POST. Cierre de sesión desde chat retira ruta antes de volver al acceso. Volver a resultados dispone panel; operaciones completadas quedan en servidor y se consultan al reabrir.

Sin backend, migraciones ni dependencias. Flutter no disponible: pruebas y validación web/Android pendientes en equipo del usuario. Revisar conversación extensa, errores y expiración de sesión.

Revertir chat_examen_panel.dart y revision_paciente_panel.dart al commit previo para recuperar panel integrado.
