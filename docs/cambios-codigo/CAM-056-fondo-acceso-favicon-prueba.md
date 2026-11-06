# CAM-056 — Fondo médico claro, favicon y prueba de acceso

Cambio solicitado tras validar visualmente el logo. Fondo ilustrado médico claro y decorativo, fuera de la tarjeta blanca; sin datos ni mensajes en la imagen. Generado con imagegen: fondo hielo azul/blanco, instrumentos discretos en bordes, centro vacío y sin texto. Se integra como asset Flutter, cubre pantalla y se excluye de semántica.

La pestaña web utiliza favicon PNG del símbolo de Vitalia. No cambia el icono de lanzador Android todavía.

La prueba integrada fallaba porque Crear cuenta de paciente estaba fuera del viewport de prueba de 800x600 tras ampliar el acceso. Se desplaza hasta el botón y espera antes de pulsarlo; conserva las comprobaciones de error y navegación. No se silencia el warning ni se elimina la aserción. También se asegura visibilidad de iniciar sesión.

Verificación Flutter pendiente en equipo del usuario: flutter analyze y flutter test. Flutter no instalado aquí. Revisión estática de archivos y assets realizada.

Reversión: restaurar acceso_page.dart, pubspec.yaml, acceso_integrado_test.dart e index.html al commit 1727ba83; retirar fondo y favicon añadidos.
