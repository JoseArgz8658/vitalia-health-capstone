# Evidencias de interfaz y esquema real

## Estado comprobado
El usuario informó flutter analyze sin incidencias y, después del ajuste CAM-069, confirmó que la prueba fallida se resolvió. No se registra un número nuevo de pruebas ni una ejecución local del asistente. Las comprobaciones con texto ampliado, emulador y capturas siguen pendientes.

## Capturas para la entrega
Usar únicamente cuentas y documentos ficticios. No capturar contraseñas, tokens, .env ni datos personales reales.

| Evidencia | Qué mostrar |
|---|---|
| Acceso y registro | Marca, campos separados y errores comprensibles |
| Historial paciente | Exámenes y estados visibles |
| Subir examen | Datos, fecha y archivo seleccionado |
| Consulta profesional | Extracción original y revisión diferenciadas |
| Resultados paciente | Copia aprobada y observaciones del profesional |
| Chat | Pregunta, respuesta, referencia al examen y aviso educativo |
| Espera y fallo | Indicador visible y mensaje que permita continuar |
| Móvil | Las mismas acciones en una pantalla estrecha |

Guardar fecha, rama/commit y resultado observado junto a cada captura. Una captura demuestra una vista; no demuestra por sí sola accesibilidad, seguridad ni veracidad médica.

## Obtener tablas y relaciones de PostgreSQL
1. Abre pgAdmin y selecciona la base de datos que utiliza Vitalia.
2. Abre Query Tool sobre esa base.
3. Abre el archivo docs/base-datos/inventario-esquema.sql de esta rama.
4. Ejecuta el script completo. Devuelve una fila con una columna schema_inventory.
5. Copia el contenido completo de esa celda y guárdalo como inventario-vitalia.json. Envíalo para compararlo con las migraciones y elaborar el diccionario de datos.

La consulta está dentro de una transacción de solo lectura y obtiene metadatos del esquema public: nombres, tipos, nulabilidad, valores por defecto, PK, FK, UNIQUE, CHECK e índices. No obtiene filas de pacientes ni credenciales. No elimina ni crea tablas. Si usas otro esquema, informar antes de adaptar el filtro public. No publiques un inventario que contenga comentarios o valores por defecto privados sin revisarlo.

## Cómo documentar el modelo
Primero representar lo realmente implementado. Una FK define una relación declarada; campos JSONB pueden contener estructuras relacionadas sin tablas independientes ni FK. Ausencia de FK no demuestra que una tabla no se use. No eliminar tablas por su nombre o porque estén vacías: hay que revisar consultas del código y migraciones.

Después diseñar por separado la ampliación: perfiles de pacientes y profesionales, clínicas/sedes, ubicación, especialidades, elección del profesional y derivación. Identificar PK/FK, obligatoriedad, unicidad y cardinalidad antes de migrar. Esta propuesta aún no se declara implementada. El diagrama actual y el propuesto deben distinguirse en la entrega.

Pendientes adicionales: mejoras de IA en ../pendientes/ia-cobertura-rendimiento.md y separación de permisos PostgreSQL en ../pendientes/seguridad-postgresql.md. Iconos Android y verificación sistemática de accesibilidad siguen abiertos en fase 6.
