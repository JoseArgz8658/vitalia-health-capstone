# CAM-084 — Perfil en consulta y edición explícita

Tras comprobar que el perfil guarda y recupera datos correctamente, ajusté su uso: Mi perfil abre en modo consulta, sin campos editables. Editar datos personales habilita el formulario. Guardar perfil vuelve a consulta solo si el servidor acepta el cambio; Cancelar edición restaura la copia cargada sin enviar una solicitud de guardado. Un error de guardado conserva la edición para corregir o cancelar. (José Aránguiz)

Organicé el contenido en tarjetas de Datos personales, Contacto e Identificación, con títulos e iconos. Las futuras funciones tendrán secciones propias. Deshabilité Actualizar perfil mientras se edita para evitar que una consulta sustituya los cambios en curso. No añadí campos, migraciones, permisos ni cambios de backend. (José Aránguiz)

## Pruebas y límites

Actualicé la prueba de guardado para exigir la entrada explícita a edición y comprobar el regreso a consulta. Añadí una comprobación de cancelación: el borrador no cambia los datos guardados y al volver a editar se recupera el valor anterior. Flutter no está instalado en el entorno de comprobación: analyze y pruebas Flutter quedan pendientes en Windows para este cambio. No repetí backend porque no se modificó su código. (José Aránguiz)

## Evidencia del incremento anterior recibida en Windows

Comprobé Flutter analyze sin incidencias y 79 pruebas Flutter aprobadas, código 0. El backend tuvo un cierre abrupto con código -1073740791 sin resumen de Jest. Probé explanations.test.cjs por separado: 28 pruebas aprobadas, código 0; después repetí la suite completa: 42 suites, 456 pruebas aprobadas y código 0. El cierre no se reprodujo y no se determinó su causa; no lo atribuí a una prueba funcional fallida. (José Aránguiz)

Apliqué profiles-app.sql desde pgAdmin como administrador en vitalia_dev: terminó en COMMIT. Inicié la aplicación y confirmé el funcionamiento del perfil antes de solicitar este ajuste visual. Este registro no demuestra instalación Docker ni una nueva prueba en Android. (José Aránguiz)

## Validación posterior del ajuste

Ejecuté flutter analyze sin incidencias y flutter test con 80 pruebas aprobadas, código 0. Comprobé visualmente los cambios y confirmé el funcionamiento del perfil organizado por secciones y la edición explícita. (José Aránguiz)
