# CAM-007 — Base de almacenamiento S3
Autorización explícita del usuario: 1 de octubre de 2026.
Archivos existentes modificados: backend/package.json, backend/package-lock.json,
backend/.env.example. Se añade @aws-sdk/client-s3 3.1144.0 con versiones fijadas.
Nuevos archivos: configuración, cliente y operaciones internas, comprobación de privacidad,
pruebas, política IAM de ejemplo y guía.

Motivo: preparar almacenamiento privado de contenido, separado de metadatos PostgreSQL.
Consecuencias: nuevas dependencias; .env requiere región, bucket y perfil solo para comprobar S3.
El arranque actual del servidor y Flutter no cambian ni dependen todavía de S3.
No se crean recursos ni se versionan credenciales. La guía implica AWS real y posible facturación.

Validación: npm ci, TypeScript y 93 pruebas aprobadas; tests S3 simulados.
Conexión a un bucket real pendiente en el equipo del usuario.
No se declara lista la carga de exámenes ni completa la fase 4.

Reversión: volver a fase-4/metadatos-documentos. No se cambia esquema ni se crean recursos AWS
al instalar o ejecutar las pruebas; recursos creados manualmente no se eliminan al cambiar de rama.
