# CAM-049: extracción por bloques y consulta automática

Autorización: «bien, con eso en cuenta, continuemos», después de proponer dividir la extracción y actualizar automáticamente el estado (7 de octubre de 2026).

El fallo real recibido fue timeout de extracción v4 a los 120011 ms. La lectura del PDF sí estaba disponible; el texto visible no constituía una extracción terminada ni permitía aprobar.

La extracción v4 ahora solicita primero examen, fecha y los catorce campos del informe. Después solicita resultados por bloques delimitados por encabezados numerados de sección. Conserva íntegramente el texto y su orden, incluido el prefijo anterior a los encabezados. Un documento sin varios encabezados reconocibles conserva sus resultados en un solo bloque: no se corta una tabla arbitrariamente. Cada bloque se valida estrictamente, incluidas las etiquetas de estado. Si alguno falla, no se devuelve ni persiste una extracción parcial para aprobación. La respuesta raw de v4 representa el JSON ensamblado de los bloques; el texto fuente y el documento S3 continúan conservados.

Contrato persistido 4 y revisión del prompt 3. La generación v3 conserva su prompt, esquema y límite previo. Las solicitudes siguen siendo secuenciales y locales, sin nuevas dependencias. Cada bloque dispone de hasta dos minutos; todo el informe comparte seis minutos. Ambos límites cancelan el transporte; no hay reintentos ilimitados. Este cambio reduce el tamaño de cada salida, pero necesita prueba real con Ollama y el PDF ficticio en el equipo del usuario. No certifica cobertura ni exactitud de la transcripción.

La consulta profesional consulta cada cinco segundos mientras el trabajo está en espera o procesándose, durante un máximo de diez minutos. Evita consultas simultáneas y no consulta durante el guardado de la revisión. Cancela el temporizador al terminar, cerrar, cambiar de consulta o desmontar la pantalla. Mantiene actualización manual. Cuando aparece una extracción terminada, vuelve a cargar el panel de revisión para habilitar el formulario; no basta con conservar su estado previo sin datos.

Pruebas: cortes sin pérdida de texto, orden, metadatos, fallo de un bloque sin entrega parcial, cancelación de dos minutos y presupuesto global de seis minutos. Integración del worker adaptada al contrato de solicitudes por etapas. Test Flutter añadido para avance automático hasta revisión y cese de consultas al terminar; Flutter no está disponible aquí y debe ejecutarse en Windows.

No hay migración nueva. Trabajos fallidos anteriores no se reintentan automáticamente. Para comprobar, reiniciar API y worker con el código compilado y subir una nueva copia ficticia.

Reversión: volver al commit 81257867bd9df9463e48c46de572ff3724a741fc. No se reescriben documentos, extracciones antiguas ni revisiones profesionales.

Resultado de comprobación local: compilación TypeScript y suite completa correctas, 40 suites y 409 pruebas; código de salida 0. Ollama, PostgreSQL, S3 y Flutter reales no están disponibles en este entorno, por lo que no se afirma validación de rendimiento ni ejecución web/Android.
