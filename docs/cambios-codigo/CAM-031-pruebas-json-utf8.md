# CAM-031 — Respuestas JSON UTF-8 en pruebas profesionales

## Motivo y alcance
Corrección dentro de la fase de revisión profesional ya autorizada. El usuario comprobó el flujo real, las 268 pruebas backend y la migración 009, pero reportó cinco fallos Flutter. Los mocks de profesional_test.dart y revision_profesional_test.dart construían respuestas sin charset; el texto ficticio incluye el carácter –, fuera de Latin-1. Se declara application/json; charset=utf-8, igual que el API real. La prueba de consulta ahora simula también GET review y comprueba que la aprobación esté deshabilitada antes de confirmar el cotejo.

## Cambios
Solo dos archivos de pruebas y este registro. Sin cambios de producción, dependencias ni migraciones. Se mantienen las comprobaciones de permisos, conflictos y conservación del original.

## Validación
Inspección de rutas, controles y fixtures realizada. Flutter no está instalado en este entorno: no se afirma que las pruebas pasaron; ejecutar flutter analyze y flutter test test/profesional_test.dart test/revision_profesional_test.dart en Windows y luego la batería completa de la fase.

## Pendiente de diseño
El usuario solicita aplazar la mejora visual. En la fase visual se deben distinguir intuitivamente el archivo original, el texto leído/OCR, la extracción IA y los datos/observaciones revisados. Considerar adolescentes y adultos mayores, lenguaje claro, jerarquía y separación, sin depender solo del color.

## Reversión
Revertir el commit de esta corrección. No afecta PostgreSQL ni S3.
