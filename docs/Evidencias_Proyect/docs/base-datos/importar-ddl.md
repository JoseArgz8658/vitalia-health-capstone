# Importar el esquema actual sin crear tablas a mano

Archivo: vitalia-importacion-datamodeler.sql. Solo para generar el diagrama; no ejecutar sobre PostgreSQL ni utilizar como migración.

## Pasos
1. Descarga los cambios de fase-6/interfaz-intuitiva.
2. Guarda tu diseño vacío si lo necesitas. En Data Modeler abre Archivo > Importar > Archivo DDL (File > Import > DDL File en la documentación). Si la traducción difiere, usa el asistente de importación DDL.
3. Selecciona docs/base-datos/vitalia-importacion-datamodeler.sql dentro del repositorio.
4. Selecciona un dialecto Oracle moderno, preferentemente 19c o posterior si está disponible. Algunos nombres de restricciones superan los 30 caracteres de versiones antiguas.
5. Avanza con el asistente y selecciona todas las tablas. Finaliza la importación. Los nombres exactos de botones dependen del asistente; no continuar si informa errores de análisis sin revisarlos.
6. Comprueba en el modelo generado que hay 17 tablas y 35 FK. El archivo contiene 123 columnas, 17 PK y las UNIQUE declaradas. Consulta relaciones-actuales.md para validar cardinalidades.
7. Envía una captura del resultado y cualquier aviso del registro. Aún no se ha probado este archivo en Data Modeler: la importación debe validarse.
8. Cuando esté correcto, ordena por áreas y guarda el diseño como Vitalia_actual. Conserva juntos archivo .dmd y carpeta asociada.

La documentación indica que importar un DDL crea un modelo relacional; no requiere ejecutar el script sobre un servidor. No conectar este archivo a tu base de datos de desarrollo.

## Equivalencias exclusivamente visuales

| PostgreSQL real | Representación del archivo Oracle |
|---|---|
| uuid | VARCHAR2(36) |
| text | VARCHAR2(4000) |
| jsonb | CLOB |
| integer | NUMBER(10) |
| bigint | NUMBER(19) |
| boolean | NUMBER(1) |
| date | DATE |
| timestamp with time zone | TIMESTAMP WITH TIME ZONE |

Estas representaciones no son equivalencias completas de validación, rango o comportamiento. VARCHAR2(4000) es un tamaño artificial para importación, no un límite que exista en todos los campos text reales. El esquema continúa siendo PostgreSQL. JSONB no se vuelve una tabla ni se pierde su estructura en la aplicación por dibujarlo como CLOB.

Se conservan nombres, columnas, nulabilidad, PK, UNIQUE completas y FK. Se omiten DEFAULT, IDENTITY, CHECK, índices y triggers en este archivo visual. Las restricciones e índices capturados están en diccionario-actual.md; el inventario no incluía triggers. Agregar notas al modelo con tipos originales y esta limitación. No presentar este DDL como reproducción completa ni prueba de integridad de PostgreSQL.

Fuentes: https://www.oracle.com/tools/technologies/faq-sql-developer-data-modeler.html y https://docs.oracle.com/en/database/oracle/sql-developer-data-modeler/21.2/dmdug/data-modeler-concepts-usage.html
