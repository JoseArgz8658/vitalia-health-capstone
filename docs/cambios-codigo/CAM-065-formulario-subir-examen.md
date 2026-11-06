# CAM-065 — Subir examen con pasos claros

Se organizó el formulario en identificación, fecha y documento, con espacio entre acciones, ejemplo de nombre, tarjeta de archivo seleccionado con tamaño y texto de espera durante la carga. Los errores se anuncian mediante Semantics liveRegion. Los pasos son secciones visibles, sin pantallas adicionales ni restricciones nuevas.

Se mantienen los tipos de examen, formato y límite de 10 MiB, validaciones, API autenticada y bloqueo de acciones durante el envío. Guardar no equivale a aprobar la extracción.

Validación: revisión del código y compatibilidad de etiquetas del test existente. Flutter no está disponible aquí; ejecutar flutter analyze y flutter test. Comprobar selección/cancelación de archivo, fecha, errores, nombre largo y carga en web y móvil.
