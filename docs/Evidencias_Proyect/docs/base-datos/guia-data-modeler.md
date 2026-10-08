# Construir el modelo actual en Data Modeler

Fuente: diccionario-actual.md y relaciones-actuales.md, derivados del inventario real del usuario. La interfaz de Data Modeler depende de la versión instalada; no se presentan nombres de menús como verificados.

1. Crea un diseño nuevo y un modelo relacional para el esquema actual. Identifica el diseño como Vitalia_actual_PostgreSQL.
2. Crea las 17 tablas con sus nombres exactos del diccionario. Registra cada atributo, tipo y obligatoriedad. NULL permitido significa opcional en almacenamiento; NOT NULL no significa necesariamente que el usuario deba escribirlo en un formulario.
3. Define las PK y las restricciones UNIQUE, incluyendo las compuestas. No marques por separado como UNIQUE las columnas de una clave única compuesta.
4. Crea cada FK usando la tabla de relaciones. En las múltiples referencias a vitalia_accounts, distingue paciente, profesional, creador y actor por el nombre de la FK.
5. Añade CHECK y predeterminados según el diccionario. Mantén UUID, JSONB y timestamp with time zone en notas si tu versión no permite representarlos exactamente; no declares una conversión como parte del esquema real.
6. Distribuye el modelo por áreas: acceso, documentos/procesamiento, asignaciones/revisiones, explicaciones/chat y auditorías. Guarda una vista general y ampliaciones legibles por área.
7. Comprueba 17 tablas, 123 columnas y 35 FK. Los índices son objetos adicionales: no cuentan como tablas.
8. Guarda el diseño nativo y exporta capturas o PDF con nombres de tablas, atributos y relaciones legibles. Añade fecha, origen del inventario y versión del proyecto en la evidencia.

No ejecutar DDL generado por Data Modeler sobre vitalia_dev. Documentar no requiere reconstruir la base ni borrar datos. Si la herramienta genera SQL para otro motor, no usarlo como migración PostgreSQL.

## Modelo lógico y relacional
El modelo lógico puede usar nombres de negocio, pero debe explicar la correspondencia con el esquema físico. Actualmente las personas se representan como cuentas y roles; una tabla Paciente con RUT no está implementada. Los JSONB contienen resultados y copias del informe, no tablas relacionales de analitos.

Conservar un segundo diseño para la propuesta futura. No presentar ese diseño como estructura ya aplicada a la aplicación.
