# CAM-057 — Registro de paciente con identidad visual

Solicitud: aplicar diseño al registro y separar campos pegados. Reutiliza fondo claro y símbolo existentes, tarjeta blanca de ancho máximo, márgenes adaptables, separación entre campos y ayuda de contraseña con salto de línea en móviles. Añade navegación de teclado entre campos, indicador de envío, mensaje accesible y acción para volver al acceso.

No cambia correo, contraseña, validación de longitud, confirmación ni API de registro. No añade datos personales futuros sin esquema backend. Sin dependencias ni assets nuevos.

Verificación estática realizada. Flutter no disponible aquí: pendiente flutter analyze, flutter test y revisión manual web/Android, con teclado y mensajes de validación.

Revertir registro_page.dart al commit cbdc43ff; sin migraciones.
