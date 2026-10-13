# CAM-081 — Restaurar el fondo de acceso

Identifiqué que el fondo vitalia-fondo-acceso.png quedó vacío al trasladar los archivos a la integración. Flutter analyze no detectó el problema, pero flutter test mostró cuatro fallos por Invalid image data. Restauré la imagen original sin cambiar el diseño ni ocultar las excepciones de las pruebas. (José Aránguiz)

## Comprobación

La imagen original contiene 1.417.641 bytes, resolución 1672 × 941 y huella Git 1ef976fde198715974ca741a7ab15b94f19ab110. Comprobé estructura PNG y decodificación, además del símbolo y favicon. Flutter no está disponible en el entorno de comprobación; la repetición en Windows se registra en la sección siguiente. (José Aránguiz)

## Evidencia Docker recibida

Ejecuté en Windows docker build --target test -t vitalia-backend-test ./backend: construcción terminada en 73,5 segundos y LASTEXITCODE 0. Las etapas npm ci, npm run build y npm test terminaron correctamente. Esta evidencia valida la imagen de pruebas, no el flujo real con PostgreSQL, S3 y Ollama. (José Aránguiz)

## Evidencia Flutter recibida

flutter pub get terminó correctamente y flutter analyze no informó incidencias. flutter test terminó con 70 pruebas aprobadas y cuatro fallidas, código 1; todas vinculadas al fondo inválido. La repetición posterior con el archivo restaurado se registra a continuación. (José Aránguiz)

## Repetición en Windows tras restaurar el fondo — 12 de octubre de 2026

Actualicé develop y repetí flutter test desde apps/vitalia en PowerShell. El resultado fue «00:08 +74: All tests passed!» y $LASTEXITCODE devolvió 0. Las 74 pruebas aprobaron después de restaurar el fondo original. El aviso sobre ocho paquetes con versiones nuevas no impidió la ejecución. Esta comprobación confirma la suite Flutter; no reemplaza las pruebas del flujo real ni una compilación Android. (José Aránguiz)
