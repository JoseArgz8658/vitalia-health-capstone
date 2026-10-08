# CAM-071 — Diccionario y relaciones del esquema local

Se leyó el inventario aportado por el usuario: exportación CSV de pgAdmin con JSON dentro, pese a extensión .json. Se generaron diccionario de atributos/restricciones/índices y tabla de relaciones con cardinalidades derivadas de FK, nulabilidad y PK/UNIQUE. Comprobación de inventario: 17 tablas, 123 columnas y 35 FK.

Se agregó guía de modelado y propuesta futura separada. No se modifica PostgreSQL ni código de aplicación. El inventario no permite declarar tablas obsoletas ni demostrar reglas de acceso del backend.

La cardinalidad inversa se calcula con restricciones completas; no se generaliza la unicidad de índices parciales. La guía exige contrastar conteos y conservar tipos PostgreSQL en notas cuando la herramienta no los represente. Data Modeler no se ejecutó en este entorno.
