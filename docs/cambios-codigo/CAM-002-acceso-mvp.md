# CAM-002 Arranque y navegación del MVP
Autorización: «autorizo esa modificacion, continuemos», 30/09/2026.
Modificados main.dart y main_vitalia.dart para usar VitaliaMvpApp; acceso_page.dart elimina import y botón de selector demo, y corrige aviso de validación.
Nuevo VitaliaMvpApp solo monta acceso. No registra rutas a paneles ni procesa autenticación simulada.
Motivo: evitar presentar el selector de roles como entrada del MVP.
Sin cambio: la entrada habitual y acceso permitirían explorar roles sin sesión. Aunque eran datos ficticios, no corresponde a presentación del producto.
Consecuencia: las pantallas protegidas no son accesibles desde el flujo habitual hasta implementar autenticación real.
No se borraron las entradas de desarrollo ni sus vistas: se mantienen para pruebas y trazabilidad. Una compilación con otra entrada demo todavía puede mostrarlas; preparar entregas únicamente con main.dart.
No se declara seguridad completa: faltan verificación de sesiones y autorización backend.
Pruebas añadidas: arranque sin selectores y validación sin navegación/sesión. Análisis y tests pendientes en equipo usuario.
Reversión: recuperar estos tres archivos de fase-2/flujo-unificado solo con autorización; nunca usar esa reversión para entrega MVP.
