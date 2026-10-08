# Cuentas locales de administrador y profesional

La herramienta crea una cuenta nueva de acceso en PostgreSQL. Utiliza el mismo hash scrypt del registro de pacientes y permite iniciar sesión por la pantalla actual. El registro público continúa creando solamente pacientes.

No hay cuentas ni contraseñas predeterminadas. No requiere otra migración o dependencia: los tres roles ya existen desde la migración 001.

## Windows PowerShell

Detén el backend con Ctrl+C. Desde la raíz del repositorio:

```powershell
git fetch origin
git switch --track origin/fase-5/cuentas-privilegiadas
cd backend
npm test -- --runTestsByPath test/privileged-accounts.test.cjs test/secret-input.test.cjs test/registration.test.cjs test/registration-router.test.cjs test/credentials.test.cjs
```

Para la prueba local puedes usar los siguientes correos ficticios, siempre que no estén registrados. No reciben mensajes ni se verifica su buzón:

```powershell
node --env-file=.env dist/database/create-privileged-account.js --role administrador --email admin.vitalia@example.com
$LASTEXITCODE
```

Escribe una contraseña propia de al menos 12 caracteres y presiona Enter. No se verán caracteres ni asteriscos: es intencional. Repite exactamente la contraseña. No la escribas en el comando ni la compartas en capturas o conversaciones. Ctrl+C cancela antes de guardar.

Resultado esperado: ID de la cuenta, role administrador, «Cuenta creada» y código 0.

Repite para profesional con otra contraseña:

```powershell
node --env-file=.env dist/database/create-privileged-account.js --role profesional --email medico.vitalia@example.com
$LASTEXITCODE
```

Después inicia el servidor:

```powershell
npm start
```

En Flutter, cierra la sesión de paciente e inicia sesión con el correo y contraseña elegidos. Para administrador debe mostrar «Cuenta: administrador» y para profesional «Cuenta: profesional». Usa la misma pantalla de acceso: no hay una URL especial. La pantalla actual de ambos roles es básica; gestión administrativa, asignaciones y revisión se incorporarán en etapas siguientes.

Si necesitas reiniciar Flutter web:

```powershell
cd C:\Users\josem\Documents\GitHub\vitalia-health-capstone-prueba\apps\vitalia
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

## Comportamiento

El comando pide contraseña y confirmación en una terminal interactiva con entrada oculta. Rechaza contraseñas cortas, discordantes o superiores a 1024 bytes; roles distintos de administrador/profesional; correos inválidos y argumentos extra. No recibe contraseñas por argumentos, variables de entorno o entrada redirigida.

Si el correo ya existe, devuelve error y código 1. No cambia su rol ni contraseña y no convierte pacientes a profesionales. Para crear ambas cuentas se necesitan correos distintos y nuevos. Un fallo de DB también devuelve error genérico y código 1, sin revelar credenciales.

Las cuentas persisten en vitalia_accounts; solo se guarda el hash de contraseña. No se imprimen hash ni contraseña. Este comando es una herramienta del operador local que ya tiene acceso a PostgreSQL; no añade un endpoint ni una sesión administrativa que gestione cuentas desde Flutter.

El rol profesional es una autorización técnica de la cuenta de prueba: no verifica habilitación, especialidad ni identidad profesional. Los permisos definitivos de exámenes y las asignaciones seguirán en backend; todavía no se concede acceso a documentos de pacientes desde este rol. No hay restablecimiento de contraseña ni cambio de rol en este alcance.

## Validación y límites

Pruebas de creación con scrypt real, verificación de contraseña e inicio de sesión de ambos roles, rechazo de entradas, correos duplicados y errores de DB. Entrada oculta probada con streams simulados y terminal Linux; comprobación de PowerShell y persistencia real pendiente en el equipo del usuario. Pruebas existentes verifican que el registro público permanece limitado a pacientes.

Crear una cuenta con el comando escribe de forma permanente. No elimines cuentas desde SQL para revertir una prueba si ya tienen sesiones, asignaciones o registros relacionados. La desactivación controlada de cuentas queda pendiente.
