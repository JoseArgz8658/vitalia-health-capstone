# Incidencias del traspaso al oficial

## Criterio de registro

Registro cada error observado y cada corrección o ajuste con su contexto, causa confirmada o hipótesis pendiente, solución aplicada y resultado de validación. Si no conozco la causa, lo indico; no doy por resuelta una incidencia solo porque deje de reproducirse. Los registros CAM anteriores conservan el estado conocido en su fecha y las actualizaciones posteriores indican el nuevo resultado. No incluyo contraseñas, tokens, archivos .env ni datos personales de pacientes. (José Aránguiz)

## Dependencias locales: tsc no se reconoce

En la carpeta del repositorio oficial, npm test no encontraba tsc. TypeScript está declarado como dependencia de desarrollo del backend y node_modules no se versiona. Instalé las dependencias con npm ci --include=dev desde backend; después la compilación pudo ejecutarse. Documenté el procedimiento para el equipo en el README y CAM-103. No instalé TypeScript globalmente. (José Aránguiz)

## Dos expectativas Flutter desactualizadas

La integración conservó los textos del asistente preliminar del equipo, pero dos pruebas todavía esperaban «Dato revisado» y el aviso anterior de extracción pendiente. Actualicé las expectativas al comportamiento conservado y añadí un caso de datos preliminares obtenidos del servidor, sin presentarlos como revisión profesional. Ajusté el lockfile a Flutter 3.44/Dart 3.12, conservando vm_service 15.4.0 comunicado desde Windows. José confirmó después flutter analyze sin incidencias y 159 pruebas correctas. Detalle: CAM-102. (José Aránguiz)

## Cierre abrupto de Node durante la suite completa

Con Node v24.15.0 y npm 11.12.1 en Windows, la ejecución terminó sin resumen y devolvió -1073740791 (0xC0000409), mientras Jest mostraba care-catalog.test.cjs. No atribuí el cierre a esa prueba: ejecutada sola aprobó 30 pruebas, salida 0. Una ejecución completa posterior aprobó 58 suites y 832 pruebas en 41.729 segundos, salida 0. La causa del cierre abrupto sigue sin determinarse; no afirmo que se corrigió actualizando Node o modificando código porque ninguna de esas acciones fue comprobada como solución. (José Aránguiz)

## Migración 025: .env no encontrado

Al ejecutar node --env-file=.env dist/database/migrate-preliminary-assistant.js desde el backend oficial, Node informó «.env: not found». El error ocurrió antes de iniciar el script y de conectarse a PostgreSQL; no era una contraseña rechazada ni dependía de credenciales de otro integrante. El archivo local del repositorio de pruebas no se trasladaba por Git. Mi primera instrucción de migración omitió comprobar este requisito; añadí la comprobación previa al manual. (José Aránguiz)

José conservaba un backend/.env funcional para el mismo PostgreSQL local y los mismos servicios. Lo copió a backend/.env del oficial, comprobando que el origen existiera y sin sobrescribir un destino existente. No publicó su contenido. Para otro integrante, corresponde su propia configuración autorizada con la plantilla o el configurador del proyecto; no copiar credenciales privadas de José ni de otros compañeros. Docker usa un .env distinto en la raíz. (José Aránguiz)

Para el traslado local entre las dos carpetas habituales de José, documenté esta comprobación y copia desde PowerShell: (José Aránguiz)

```powershell
$carpetaGitHub = Join-Path $env:USERPROFILE "Documents\GitHub"
$origen = Join-Path $carpetaGitHub "vitalia-health-capstone-prueba\backend\.env"
$destino = Join-Path $carpetaGitHub "vitalia-health-capstone\backend\.env"

if (!(Test-Path -LiteralPath $origen -PathType Leaf)) {
    throw "No se encontró el archivo .env local del repositorio de pruebas."
}
if (Test-Path -LiteralPath $destino) {
    throw "El destino ya existe. No se sobrescribió; revisar la configuración local."
}

Copy-Item -LiteralPath $origen -Destination $destino -ErrorAction Stop
Test-Path -LiteralPath $destino -PathType Leaf
```

Si las carpetas están en otra ubicación, ajustar sus rutas. Esta copia solo corresponde al mismo entorno local y no modifica la base de datos. Antes de repetir la migración, mantener el respaldo y utilizar postgres únicamente para la administración; la API continúa con vitalia_app. (José Aránguiz)

Con el respaldo confirmado, José repitió el bloque de migración y verificación con restauración de las variables de entorno al finalizar. Comunicó estos resultados: (José Aránguiz)

```text
Migración de compatibilidad del asistente preliminar aplicada.
Compatibilidad del asistente preliminar: esquema 025 y permisos correctos. Verificación de solo lectura.
```

Registro con ello la migración 025 aplicada y el verificador de esquema y permisos correcto en PostgreSQL local. No deduzco de esta salida una prueba manual completa del asistente ni una nueva validación Docker. (José Aránguiz)

## Auditoría de dependencias pendiente

La instalación informó 23 vulnerabilidades (3 bajas, 17 moderadas y 3 altas) y obsolescencia de glob 10.5.0. No las declaro resueltas porque las pruebas hayan aprobado. Sigue pendiente analizar las rutas de npm audit y npm audit --omit=dev; no apliqué correcciones automáticas ni cambios de dependencias en este registro. (José Aránguiz)
