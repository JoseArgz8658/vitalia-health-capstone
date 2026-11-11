# CAM-079 — Respaldo y restauración desde pgAdmin 4

Fecha de comprobación: 12 de octubre de 2026, hora de Chile.

## Evidencia comunicada — José Aránguiz

Preparé un respaldo Custom de vitalia_dev desde pgAdmin 4 en Windows, fuera del repositorio, para entregarlo de forma privada al equipo. Incluí pre-data, data y post-data, tablas, secuencias y objetos del esquema public. Omití propietarios, privilegios y tablespaces para no depender de usuarios o ubicaciones de mi instalación. No se publica aquí el respaldo ni sus datos. (José Aránguiz)

El primer intento en vitalia_verificacion_backup terminó con código 1: el respaldo intentó CREATE SCHEMA public, pero la base nueva ya tenía ese esquema. El registro continuó restaurando objetos; esa copia no se declaró como una restauración limpia. No se volvió a restaurar encima de ella.

Creé vitalia_verificacion_backup_2 para una comprobación nueva. Retiré únicamente su esquema public vacío mediante un bloque que verifica current_database() y DROP SCHEMA sin CASCADE. Restauré como postgres, sin propietarios, privilegios ni tablespaces. pgAdmin informó Successfully completed. El comando comunicado no incluía --single-transaction ni --exit-on-error; no doy esas opciones por utilizadas.

El registro mostró creación de 17 tablas, dos secuencias, función de inmutabilidad, índices, trigger y claves foráneas. Comparé los conteos de cuentas, documentos, procesamientos, revisiones, turnos de chat y migraciones entre vitalia_dev y vitalia_verificacion_backup_2. Confirmé que coinciden; no se comunicaron las cifras individuales. Esta comparación no equivale a comparar cada campo ni a comprobar la aplicación contra la copia. (José Aránguiz)

## Alcance y pendientes

El respaldo corresponde al PostgreSQL de Windows, no al volumen Docker. Conserva referencias a objetos S3 pero no incluye los PDF o imágenes. Los objetos del bucket compartido siguen siendo los mismos para las distintas copias de la base. Los cambios de PostgreSQL no se sincronizan entre computadores.

La restauración como postgres sin privilegios no prepara el rol vitalia_app ni sus permisos. El usuario ya mencionó ese rol en su instalación, pero sus atributos y concesiones actuales deben comprobarse antes de modificar permisos. Pendientes: permisos mínimos en la copia, comprobación controlada de la aplicación, revisión del contenido antes de compartir y restauración por compañeros.

El respaldo puede incluir cuentas, hashes de contraseña, sesiones, auditorías y conversaciones. Se entregará por canal privado tras revisar que contiene solo información apta para las pruebas del equipo. No se comparte la contraseña del servidor PostgreSQL ni archivos .env.

## Reversión y conservación

No se modificó vitalia_dev mediante la restauración. Se conservaron el archivo de respaldo y la base original. Las bases de verificación son copias independientes; cualquier limpieza posterior debe identificar explícitamente la copia y no tocar la original.

## Comprobación posterior de permisos — José Aránguiz

Comprobé que vitalia_app permite login y no tiene los atributos superusuario, crear bases ni crear roles. Las 17 tablas de la copia pertenecen a postgres. Apliqué concesiones de conexión, uso de esquema, lectura, DML para tablas operativas, inserción para revisión y auditorías y uso/lectura de secuencias, únicamente en vitalia_verificacion_backup_2 mediante transacción y verificación de nombre.

Conecté desde Node como vitalia_app utilizando la configuración local sin modificar el .env, con destino explícito a la copia. La consulta devolvió 10 documentos, 4 revisiones y código de salida 0. No ejecuté escrituras ni el flujo completo de la aplicación contra esta copia. No cambié los permisos de vitalia_dev ni la contraseña del rol. Los permisos de la copia no están en el respaldo original, por lo que deben aplicarse tras la restauración por cada compañero. (José Aránguiz)
