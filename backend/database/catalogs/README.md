# Catálogo territorial de Chile

Incorporé una copia normalizada de la planilla pública `CUT_2018_v04.xls` de SUBDERE: 16 regiones, 56 provincias y 346 comunas. Conservé nombres y códigos como texto, incluidos sus ceros iniciales. Eliminé únicamente espacios exteriores y la columna de abreviatura regional que no utiliza este esquema. No agregué territorios ficticios. Esta versión corresponde al catálogo publicado como actualizado al 2018; no la presento como una revisión de cambios territoriales posterior. (José Aránguiz)

- Fuente: https://www.subdere.gov.cl/documentacion/c%C3%B3digos-%C3%BAnicos-territoriales-actualizados-al-06-de-septiembre-2018
- Archivo: https://www.subdere.gov.cl/sites/default/files/documentos/CUT_2018_v04.xls
- Consulta: 29 de octubre de 2026.
- SHA-256 del XLS descargado: `d1b7fc3abb93cea3d115861579297d8bbdc9a7c762c958e646cd01b804df1ea0`.
- SHA-256 del JSON con finales de línea LF: `6abd3fc3c73cc687ad4e1d8b01b83981026716456c0f70bc02c690f61565ca03`.

Extraje las columnas código/nombre de región, provincia y comuna de las 346 filas, comprobé duplicados y jerarquía y ordené cada colección por código. El JSON versionado permite ejecutar el backend sin consultar SUBDERE en cada inicio. No instalé herramientas de planillas como dependencias del proyecto. (José Aránguiz)

La carga se ejecuta deliberadamente con `node --env-file=.env dist/database/load-territories.js` desde backend y una identidad administrativa de `vitalia_dev`. Exige la migración 012, conserva las migraciones aplicadas y compara el catálogo existente dentro de una transacción. Agrega filas faltantes que coinciden con esta versión; si encuentra códigos, nombres o relaciones incompatibles, revierte en lugar de sobrescribir. Repetir una carga completa y coincidente no modifica datos. (José Aránguiz)

El script está limitado a `vitalia_dev`; no se añade a migrate-all ni a Compose. La lectura por API requiere SELECT para vitalia_app en las tres tablas; no concede escritura del catálogo a la aplicación. Para usar otro destino se requiere un procedimiento específico revisado. (José Aránguiz)
