# Preparar una sesión de usabilidad del SIL

Registra el commit con `git rev-parse --short HEAD`. Ejecuta el piloto y las
sesiones en el ambiente aislado. Usa la matriz y el plan vigentes como pauta
de observación.

## Arranque local

En Windows, con Docker Desktop y Flutter, desde la raíz de esta rama:

```powershell
.\deploy\showcase.ps1 -Action Start -FlutterCommand 'C:\ruta\flutter\bin\flutter.bat'
.\deploy\showcase.ps1 -Action Credentials
Start-Process msedge 'http://127.0.0.1:5174'
```

Si Flutter está en el PATH, puedes omitir `-FlutterCommand`. El proyecto
Compose `vitalia-usability` tiene base, red y volumen dedicados. La base se
inicializa con las migraciones de repositorio hasta el esquema 046. La API
y PostgreSQL no publican puertos al host. La web se publica en loopback.
Para evaluar el diseño móvil desde el computador, usa la vista adaptable
del navegador. Para usar un teléfono físico, necesitarás un acceso privado
autorizado al ambiente de pruebas.

Las claves salen de `.env.usability`, excluido de Git. Las cuentas de ejemplo
incluyen administración, un operador revisor y una paciente con 54 informes.
Para contrastar permisos, usa también
`francisca.valenzuela.central@altocanelo.example.invalid`, con la clave de
operador del entorno. Tiene acceso operativo sin permiso de publicación.
Las credenciales de este entorno son compartidas por rol. Usa sesiones
separadas del navegador y registra el identificador del participante aparte.

Hay 2 laboratorios, 6 sedes, 132 pacientes, 10 operadores, 660 órdenes, 416
informes publicados y 72 derivaciones pendientes. Las muestras y resultados
mantienen el alcance del SIL postanalítico. La asistencia que requiera
un modelo local debe verificarse por separado. Este Compose no incluye
Ollama ni servicios externos.

Para detener el ambiente y conservar los datos:

```powershell
.\deploy\showcase.ps1 -Action Stop
```

El moderador puede restaurar el escenario inicial entre sesiones con
`-Action Reset -ConfirmRemoval`. Para retirar los recursos del proyecto de
pruebas, usa `-Action Remove -ConfirmRemoval`. Estos comandos eliminan el
volumen aislado y sus credenciales. Conserva primero las evidencias de la sesión.

## Preparar las tareas

- **ADM-01 a ADM-06.** Preparar los dos laboratorios y sus sedes, una cuenta
  vinculada y otra por incorporar. Observar cambio de contexto, incorporación,
  vinculación, cambio de permiso, auditoría y lectura de indicadores.
- **OPE-01 a OPE-06.** Preparar un PDF sintético de solicitud y uno de informe
  autorizado para la orden elegida. Observar recepción, revisión de campos
  sugeridos, asociación, búsqueda de pacientes, publicación y recuperación
  de órdenes. Usar una orden sin informe para la carga y una autorización
  ficticia explícita.
- **PAC-01 a PAC-06.** Preparar una invitación nueva y un código con el operador.
  Usar la cuenta con historial para buscar, consultar, descargar, comparar,
  revisar la orientación y localizar recuperación de acceso.

El moderador describe el objetivo de la tarea y observa sin señalar controles.
Registra si se completó, intentos, ayuda, errores, observaciones y resolución
de pantalla. Las verificaciones automatizadas no representan resultados de
participantes.
