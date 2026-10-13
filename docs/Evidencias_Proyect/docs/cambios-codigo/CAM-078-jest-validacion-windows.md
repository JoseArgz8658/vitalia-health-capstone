# CAM-078 — Jest y validación de ejecución en Windows

Fecha: 12 de octubre de 2026. Evidencia: salidas de terminal y comprobaciones manuales comunicadas por José. Cambio de dependencias: c9df999.

## Actualización y pruebas

Jest pasa de 30.2.0 a 30.5.2 con versión exacta y package-lock actualizado mediante npm. npm test compiló TypeScript y aprobó 423 pruebas de 40 suites en Windows. Los avisos de console.warn aparecen en casos que simulan fallos y no significan que la suite haya fallado.

npm audit pasó de 32 avisos (27 altos y 5 moderados) a 19 moderados. npm audit --omit=dev reportó cero vulnerabilidades en ambas comprobaciones. La auditoría completa NO está limpia.

## Riesgo residual

La cadena de desarrollo es Jest > @jest/transform > babel-plugin-istanbul 8.0.0 > @istanbuljs/load-nyc-config 1.1.0 > js-yaml 3.15.2 > argparse 1.0.10 > sprintf-js 1.0.3. Los 19 avisos incluyen paquetes afectados por esa cadena; no representan 19 fallos independientes.

GHSA-hp3w-g68c-fv3c afecta sprintf-js hasta 1.1.3 y no identifica una versión corregida al consultar el aviso. Subir únicamente a 1.1.3 no elimina el problema. npm audit fix --force propone Jest 25.0.0 y no se aplicó. No se fuerza js-yaml 4 dentro de un consumidor que requiere 3. El Dockerfile elimina devDependencies en la imagen final, pero las herramientas de desarrollo y construcción siguen incluidas en el seguimiento del riesgo.

Pendiente: revisar corrección del proveedor o sustitución compatible y probar la cadena antes de cambiarla. No procesar configuraciones de pruebas de origen no confiable. Este resultado no certifica ausencia de todas las vulnerabilidades del proyecto.

Aviso: https://github.com/advisories/GHSA-hp3w-g68c-fv3c

## Comprobaciones funcionales del entorno

Docker Desktop 29.8.0, Compose 5.5.1 y WSL 2. PostgreSQL Docker saludable y migraciones 001 a 011 aplicadas con código 0. Un error de nombre del bucket en el .env de la raíz provocó NoSuchBucket; tras corregirlo se comprobó S3 privado. backend/.env corresponde al entorno sin Docker.

La extracción inicial sin aceleración configurada superó el tiempo (193807 ms). Al habilitar compose.gpu.yaml, Ollama informó reparto CPU/GPU con RTX 3050 de 4 GB y la nueva extracción terminó requires_review. Esto acredita esa prueba, no un tiempo garantizado ni GPU completa. API, worker y consultas se mantuvieron funcionales después de stop/up, conservando cuentas y revisión.

José confirmó el recorrido paciente–extracción–profesional–paciente con Docker y posteriormente sin Docker. El nuevo PDF ficticio lipídico/hormonal mostró fechas con barras y campos omitidos; tras cotejo manual y corrección de la copia revisada, se aprobó y se consultó como paciente. No se presentan las incidencias originales como eliminadas.

Windows bloqueó impellerc.exe por control de aplicaciones. El usuario cambió esa configuración y pudo ejecutar Flutter; no se recomienda desactivar protecciones como requisito general del proyecto.

## Pendientes separados

Mejorar extracción de fechas y referencias multilínea y mensajes de validación que identifiquen el campo. Documentar diferencias entre advertencias originales y copia revisada. Android, web compilada con Nginx, restauración de respaldos e instalación en otros computadores no se comprobaron en esta sesión. No se cambian migraciones, permisos ni datos desde esta actualización.

## Reversión

Revertir el commit de actualización de package.json y package-lock.json, ejecutar npm ci y repetir pruebas. Con ello volverían las dependencias anteriores y sus avisos. No hay cambios en bases de datos.
