# CAM-042 — Procesador automático, Docker y distribución limpia

## Autorización
El usuario autorizó continuar las fases y pidió Docker, una rama limpia para trasladar él mismo al repositorio oficial y una guía comprensible de requisitos/ejecución web y Android. No se escribe en el repositorio oficial.

## Cambios
Procesador secuencial de cola con bloqueo advisory por sesión, compartido con el CLI manual. Recupera trabajos que quedaron processing señalándolos failed/processing_interrupted al adquirir el bloqueo exclusivo. No reencola fallos ni modifica aprobaciones. Espera modelos instalados; un resultado no confirmado o pérdida de sesión detiene el proceso. Cierre ordenado con señales.

Modo container explícito permite solo PostgreSQL postgres y destinos IA internos prefijados; modo actual conserva loopback. Migrador unificado aplica SQL ordenado con los mismos checksums y registros. Nuevos comandos npm worker y migrate.

Docker: API, worker, migrador, PostgreSQL, Ollama y web opcional servida por nginx desde compilación Flutter. Etapa test separada, dependencias de desarrollo fuera de imagen runtime; configuración privada generada fuera de git, puertos solo loopback y volúmenes persistentes. GPU NVIDIA opcional. Sin crear recursos S3 ni copiar credenciales. Sin nuevas dependencias npm.

Distribución: conservar aplicación Flutter alcanzable desde main.dart, Android/web, backend funcional, migraciones, pruebas del producto y deploy; quitar documentos de avance/cambios, AGENTS, scripts IA y de preparación Android, checks/evaluaciones/verificadores manuales no necesarios, demostraciones Flutter no usadas y .env.example. README único con instalación, uso, pruebas y transferencia manual. Se conservan los archivos binarios Android por SHA desde la rama original.

## Verificación y límites
Compilación y batería completa de 373 pruebas en 37 suites aprobadas. Pruebas de bloqueo, recuperación, consumo de cola, estado no confirmado y destinos locales/contenedor. Docker/Flutter/PowerShell/PostgreSQL real no están disponibles en este entorno: validación completa debe ejecutarse en el equipo del usuario. El entorno Docker usa su propia base/modelos; no migra automáticamente la instalación previa de Windows. AWS sigue siendo externo y requiere acceso autorizado.

## Reversión
La rama de trabajo preserva archivos anteriores y el histórico. Volver a fase-5/chat-examen para modo anterior. Detener worker antes del comando manual. No borrar volúmenes ni documentos S3. Rama de distribución es independiente y puede descartarse sin afectar main ni el repositorio oficial.
