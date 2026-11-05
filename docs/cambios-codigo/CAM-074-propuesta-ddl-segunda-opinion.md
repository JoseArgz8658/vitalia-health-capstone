# CAM-074 — DDL visual ampliado y segunda opinión

Se incorporan decisiones del usuario: teléfono opcional, un responsable por examen y derivación intraclínica. La propuesta añade roles globales múltiples y revisiones por atención para permitir una segunda opinión posterior sin sobrescribir la previa.

Generado desde estructura declarativa: 18 tablas / 105 columnas / 33 FK nuevas; junto con base actual 35 tablas / 228 columnas / 68 FK. Separado del esquema real; no se ejecutan migraciones. Se documentan índices parciales y reglas de backend omitidas por el archivo visual, transición de aprobaciones y limitación de FK a revisión previa nueva.

Conteos verificados con generador. Importación en Data Modeler y decisiones restantes pendientes. No se declara implementada segunda opinión ni multiclínica en aplicación.
