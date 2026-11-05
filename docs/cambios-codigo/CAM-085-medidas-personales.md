# CAM-085 — Medidas personales opcionales e historial propio

Añadí Medidas personales como módulo separado dentro de Mi perfil del paciente. Abre en consulta y Registrar medidas habilita el formulario. Peso en kg y altura en cm son opcionales individualmente; se requiere al menos uno, mayor que cero y finito. Admití coma decimal en el formulario y conservé unidades explícitas para evitar confundir metros con centímetros. No establecí rangos clínicos ni calculé diagnósticos o recomendaciones. (José Aránguiz)

Cada registro conserva su fecha. Al iniciar se propone el momento actual; al elegir otro día se utiliza el inicio de ese día en la zona local y se envía UTC. No permito fechas futuras. El historial muestra como máximo los veinte registros más recientes. No sobrescribo medidas anteriores ni ofrezco borrado o edición del historial en este incremento. Cancelar registro no envía datos. Se bloquea la actualización global del perfil mientras se introduce una medida para no perder el borrador. (José Aránguiz)

## API y permisos

Añadí GET/POST /api/profile/measurements. Solo el rol paciente puede usarlos; la persona se obtiene de la cuenta de sesión y debe tener perfil paciente previamente guardado. El cliente no elige person_id, source ni recorded_by: fijo la fuente patient_reported y el autor desde la sesión. No envío estas medidas al asistente ni las presento como confirmadas por un profesional. (José Aránguiz)

El guardado usa un UUID de solicitud, conservado al reintentar el mismo formulario. Un reintento con contenido idéntico devuelve el mismo registro; reutilizar ese UUID con otra persona o contenido produce conflicto sin revelar el registro ajeno. Mantengo la transacción y el bloqueo por cuenta; no uso una transacción durante interacción del formulario. (José Aránguiz)

Amplié profiles-app.sql únicamente con SELECT e INSERT por columnas sobre patient_measurements. No concedí UPDATE ni DELETE sobre las medidas, ni añadí migraciones o dependencias. Se debe revisar y volver a ejecutar deliberadamente ese archivo administrativo en vitalia_dev antes de probar las medidas con vitalia_app. No modifiqué la base del equipo, no repetí 012 y no cambié el repositorio oficial. (José Aránguiz)

## Validación

Compilé TypeScript y ejecuté Jest: 43 suites y 482 pruebas aprobadas, código 0. Añadí casos para medidas nulas, cero, negativas, NaN/Infinity, fechas inválidas/futuras, campos de identidad no permitidos, perfil ausente, rol incorrecto, autor de sesión, consulta propia, repetición y conflictos. (José Aránguiz)

En un motor PostgreSQL PGlite aislado comprobé el servicio con un rol vitalia_app limitado: guardado, lectura propia, reintento sin duplicados, conflictos por contenido y por propietario, y denegación de UPDATE/DELETE de medidas. No equivale a la comprobación pendiente en PostgreSQL 16 del equipo. No incorporé ese motor como dependencia del proyecto. (José Aránguiz)

Añadí dos pruebas Flutter: registro con coma decimal y una medida omitida; cancelación sin envío y reintento con el mismo identificador. Flutter no está instalado en el entorno de comprobación: analyze y tests de este módulo quedan pendientes en Windows. Las 80 pruebas recibidas corresponden al incremento anterior CAM-084. (José Aránguiz)

## Pendientes conservados

Continúan pendientes el catálogo territorial oficial y la selección de comuna, las clínicas y sucursales, invitaciones institucionales, atención por examen y la consulta preliminar del asistente. La auditoría específica de cambios de perfil/medidas y las políticas de rectificación del historial deben definirse antes de su despliegue real. No considero cerrada la fase 7 por añadir este módulo. (José Aránguiz)

## Validación posterior en Windows — 29 de octubre de 2026

Ejecuté flutter analyze sin incidencias y flutter test con 82 pruebas aprobadas, código de salida 0. Ejecuté npm test: TypeScript compiló y aprobaron 482 pruebas en 43 suites, código de salida 0. Los console.warn corresponden a escenarios de fallo provocados por las pruebas; la suite completa terminó aprobada. Los avisos de versiones nuevas de paquetes no impidieron la validación y no actualicé dependencias en este paso. (José Aránguiz)

Apliqué el archivo completo backend/database/permissions/profiles-app.sql en vitalia_dev mediante pgAdmin; terminó en COMMIT, sin errores, en 532 ms. Después probé el módulo desde la aplicación y confirmé que las medidas se guardan y permanecen al salir y volver a abrir el perfil. Esta comprobación acredita guardado y recuperación en el entorno local; no la presento como una nueva prueba de cancelación, aislamiento entre cuentas o rechazo de todos los valores inválidos. (José Aránguiz)

Conservo pendientes el catálogo territorial y la selección de comuna, la auditoría específica de perfiles/medidas, la política de rectificación y los bloques de clínicas, invitaciones y atención. El resultado no cierra toda la fase 7 ni modifica el repositorio oficial. (José Aránguiz)

## Comprobaciones manuales adicionales — 29 de octubre de 2026

Confirmé cancelación sin registro nuevo, rechazo de peso cero o negativo y separación de medidas al ingresar con otro paciente. Estos recorridos se suman al guardado y recuperación comprobados. El catálogo territorial posterior se registra por separado en CAM-086. (José Aránguiz)

