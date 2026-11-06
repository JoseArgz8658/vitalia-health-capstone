# CAM-083 — Perfil propio y validación de RUT

Conecté GET/POST /api/profile con la identidad obtenida de la sesión. Añadí Mi perfil a las pantallas de paciente y profesional, con formulario espaciado, indicador de carga y mensajes de consulta/guardado. El perfil es opcional y no bloquea el acceso a exámenes existentes. No cambié el registro público, las asignaciones ni la fuente de datos del asistente. (José Aránguiz)

Normalicé el RUT con o sin puntos y con K mayúscula, comprobando el dígito mediante módulo 11. Un resultado matemáticamente válido no acredita identidad ni existencia del titular. El RUT y teléfono siguen opcionales mientras se acuerda la política de identificación. No añado pasaportes ni otros documentos antes de definir su política. Un RUT ya registrado no puede vaciarse desde este formulario, y uno verificado no puede cambiarse mediante esta API. (José Aránguiz)

Separé perfil y permisos: el backend rechaza accountId, roles, identificadores de otra persona y estados de verificación enviados como campos extra. Los perfiles se crean según el rol existente, nunca según una elección del cliente. La cuenta profesional conserva su estado pendiente y no obtiene permisos de jefe clínico. El administrador no tiene acceso a esta pantalla ni a los perfiles clínicos mediante estas rutas. (José Aránguiz)

Serialicé el guardado por cuenta y añadí una revisión para rechazar ediciones obsoletas. El guardado es transaccional, incluido el identificador, de modo que un conflicto de RUT no deje cambios parciales. Los mensajes de conflicto no identifican al titular de otra cuenta. No registro cuerpos de solicitudes ni respuestas con datos personales. Al expirar la sesión se cierran las rutas abiertas, incluida Mi perfil. (José Aránguiz)

## Permisos y compatibilidad

Preparé backend/database/permissions/profiles-app.sql para aplicación administrativa deliberada en vitalia_dev. Solo concede SELECT, INSERT por columnas y UPDATE por columnas requeridas; no concede DELETE, DDL ni modificación de verification_status, role_code o account_id. No cambia propietarios ni revoca concesiones anteriores. Rechaza un destino distinto o un vitalia_app con atributos administrativos. No se ejecuta automáticamente por migrate-all. La nueva pantalla muestra indisponibilidad si faltan tablas/permisos, sin impedir el funcionamiento de los exámenes. (José Aránguiz)

No edité la migración 012 ya aplicada ni añadí migraciones. El formulario todavía no captura medidas ni ofrece comuna porque el catálogo territorial está vacío. La fecha de nacimiento puede guardarse vacía: ese perfil paciente se informa como incompleto. No envío nuevos datos al chat. (José Aránguiz)

## Validación

Compilé TypeScript y ejecuté Jest: 42 suites y 456 pruebas aprobadas. En PGlite aislado probé el servicio con un rol vitalia_app limitado y concesiones por columna: creación y actualización, normalización del RUT, separación entre dos cuentas, conflicto de identificación con rollback, guardado obsoleto, RUT verificado protegido y denegación de DELETE y cambios del estado de verificación. El guard de base de destino rechazó primero el esquema de comprobación; solo para la prueba aislada adapté el nombre permitido. No se ejecutó ese script en la base del equipo. (José Aránguiz)

Añadí tres pruebas Flutter para el formulario, expiración y uso de sesión en la ruta fija. Flutter no está instalado en el entorno de comprobación: analyze, tests, visualización web y Android quedan pendientes en Windows. No declaro esas pruebas aprobadas hasta recibir su salida. (José Aránguiz)

## Referencias y uso

- [SII: dígito verificador incorrecto](https://www.sii.cl/preguntas_frecuentes/preguntas_generales/001_430_5071.htm).
- [SII: formato de comprobantes, módulo 11 y K mayúscula](https://www.sii.cl/ccp/formato_envio_cp_electronico.pdf).
- [Guía del bloque](../fase-7/bloque-1-perfiles-ubicacion.md).
