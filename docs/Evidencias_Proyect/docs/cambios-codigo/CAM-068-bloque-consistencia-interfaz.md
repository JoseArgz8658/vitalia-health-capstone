# CAM-068 — Bloque de consistencia de interfaz

## Cambios agrupados
- MensajeVista compartido: icono y texto legible, errores con color y anuncio semántico.
- Márgenes de 16 en pantallas menores de 600 y 24 en escritorio para historial, lista de pacientes, consulta profesional y resultados.
- Listas profesionales: carga con mensaje visible, avisos vacíos con iconos y acciones que permiten distribuirse en varias filas.
- Explicaciones: tarjeta por indicador, título, separación de definición/fuente y aviso educativo.
- Avisos consistentes en procesamiento y resultados; plan de fase actualizado separando implementado y pendiente.

## Alcance y validación
No se modifican API, datos, permisos, aprobación ni generación de IA. Revisión estática de imports y etiquetas existentes; Flutter no está disponible en este entorno, por lo que no se declara analyze ni tests ejecutados.

Una ronda: flutter analyze y flutter test. En web y móvil comprobar historial/lista vacíos, examen con nombre largo, resultados y explicación con varios indicadores, error de consulta, navegación de regreso y botón flotante. Con teclado y tamaño de texto aumentado comprobar que se leen títulos/acciones y no se tapa contenido. Conservar capturas y resultados reales para el informe.
