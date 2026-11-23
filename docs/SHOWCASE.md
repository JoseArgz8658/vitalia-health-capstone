# Vitalia Health en modo demostración

Showcase ejecuta el Flutter original y los servicios SIL principales. Docker
Compose crea el proyecto `vitalia-showcase`, con PostgreSQL 16, la base
`vitalia_showcase`, un volumen propio, un backend y una web propios. Solo se
publica la web en `127.0.0.1:5174`. PostgreSQL y la API están en una red interna.
La compilación web se escribe en `apps/vitalia/build/showcase`, separada de
`build/web`. La instalación de `5173` se administra por separado.

## Windows y Docker Desktop

Con Docker Desktop iniciado y Flutter disponible en PowerShell, ejecuta desde la
raíz del repositorio en la rama de la demostración:

```powershell
.\deploy\showcase.ps1 -Action Start
.\deploy\showcase.ps1 -Action Credentials
Start-Process msedge 'http://127.0.0.1:5174'
```

Las contraseñas de demostración se generan con aleatoriedad criptográfica en la
primera ejecución. Se guardan en `.env.showcase`, excluido de Git. El comando
`Credentials` las muestra en la consola local. Mantén ese archivo y la salida
de consola fuera del repositorio y de grabaciones o capturas compartidas.

| Cuenta | Entrada | Qué probar |
| --- | --- | --- |
| `admin@showcase.example.invalid` | Administración | Monitoreo de dos laboratorios, seis sedes, operadores y actividad |
| `operador-001@showcase.example.invalid` | Personal de laboratorio | Órdenes y solicitudes de una sola sede |
| `operador-002@showcase.example.invalid` | Personal de laboratorio | Dos sedes y búsqueda paginada |
| `operador-003@showcase.example.invalid` | Personal de laboratorio | Todas las sedes de Cordillera, revisión y publicación |
| `paciente-001@showcase.example.invalid` | Paciente | 54 informes, navegación de dos páginas, PDF y comparación |

La carga inicial es transaccional y se ejecuta una vez por volumen. Repetir
`Start` conserva los cambios hechos en la demostración y evita duplicados.
La clínica sintética usa el catálogo real del SIL, con PDFs generados, valores
de glucosa y HbA1c para comparar y fechas relativas al día de inicialización. Contiene
132 pacientes (120 en Cordillera), 10 operadores, 660 órdenes, 416 informes
publicados y 72 derivaciones pendientes. Los eventos insertados por el generador
llevan `showcase: true` y `origin: synthetic_seed` en sus detalles. Toda la
aplicación muestra «Entorno de demostración — Datos ficticios».

## Detener, regenerar y retirar

```powershell
.\deploy\showcase.ps1 -Action Stop
.\deploy\showcase.ps1 -Action Reset -ConfirmRemoval
.\deploy\showcase.ps1 -Action Remove -ConfirmRemoval
```

`Stop` conserva el volumen y las claves. `Reset` retira únicamente el volumen
showcase, vuelve a cargar el escenario y genera claves nuevas. `Remove` retira
los contenedores, redes, el volumen showcase y su `.env.showcase`. La imagen y
la compilación web se pueden reutilizar. La confirmación explícita se exige
porque se eliminan los cambios hechos dentro de la demostración.

## Verificación reproducible

Con Node.js disponible y una instancia showcase recién iniciada:

```powershell
node --env-file=.env.showcase backend/test/showcase-journey.cjs
```

El recorrido verifica permisos de laboratorio y sede, seis páginas del
directorio, búsqueda, indicadores, perfil, informes paginados, descarga y
comparación PDF. La CI incluye las suites existentes y el recorrido en Edge.
Showcase no trae un servicio Ollama ni usa Google Maps, correo o servicios
externos. Las funciones que requieren esos proveedores quedan limitadas al
comportamiento local disponible en Vitalia. Las rutas S3 de otras áreas del
proyecto quedan fuera del showcase postanalítico.
