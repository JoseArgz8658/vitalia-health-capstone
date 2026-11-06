# CAM-010 — Corrección de sintaxis en cliente Flutter
Corrección del alcance previamente autorizado, a partir de la salida flutter analyze del usuario.

Causa: la inserción de métodos mediante reemplazo de texto interpretó el patrón literal $'
de las expresiones regulares como una referencia de sustitución e insertó fragmentos repetidos.
Resultado: auth_api.dart mal formado y errores de métodos inexistentes en cadena.

Cambios: reconstruir auth_api.dart a partir del cliente previo válido e insertar los métodos de
documentos con sustitución literal; conservar login/me/register/logout.
Retirar import innecesario dart:typed_data de guardar_documento.dart.

Verificación local: analizador sintáctico tree-sitter-dart sin errores en nueve archivos Dart de
la entrega. Esto no sustituye flutter analyze ni las pruebas de Flutter, pendientes en equipo usuario.
Sin cambios en backend, dependencias, .env, PostgreSQL ni S3.
