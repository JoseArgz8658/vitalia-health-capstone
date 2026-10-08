# CAM-072 — DDL para importación visual

Por solicitud del usuario se generó un DDL de representación Oracle desde el inventario local PostgreSQL. Se preservan 17 tablas, 123 columnas, 17 PK, UNIQUE y 35 FK. Generación primero de tablas y luego claves, con las FK al final, para evitar referencias a objetos aún no definidos.

Se documentan tipos artificiales y omisión de restricciones específicas/identidades/predeterminados/índices/triggers. No es migración ni DDL para ejecutar en PostgreSQL. La documentación oficial de Oracle menciona importación Oracle, DB2 y SQL Server; no se promete importar PostgreSQL directamente.

Comprobados conteos del generador contra inventario. No hay instalación ejecutable de Data Modeler aquí; pendiente validación del parser y diagrama en el equipo del usuario.
