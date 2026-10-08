# Consulta profesional de exámenes y extracciones

## Alcance

El profesional entra a Mis pacientes, selecciona Ver exámenes y consulta el historial de un paciente con asignación activa. Puede descargar el original y consultar la extracción, el texto utilizado y las incidencias. Todo sigue sin aprobación. No hay modificación de datos, corrección, aprobación ni explicación al paciente en este cambio.

El servidor comprueba rol y asignación activa en cada solicitud. Los pacientes y administradores no reciben acceso por estas rutas. Conocer un ID no concede acceso. La consulta no inicia procesamiento ni llama a IA.

## Windows: migración y comprobación

Detén backend y Flutter con Ctrl+C. Desde la raíz:

```powershell
git fetch origin
git switch --track origin/fase-5/consulta-profesional
cd backend
npm test
node --env-file=.env dist/database/migrate-professional-access.js
node --env-file=.env dist/database/verify-professional-access.js
$LASTEXITCODE
npm start
```

Espera «Migración de acceso profesional aplicada» (o ya aplicada) y «Acceso profesional, aislamiento y auditoría correctos. Datos sintéticos revertidos; S3 sustituido», código 0. La migración 008 requiere 007. El servidor requiere la nueva tabla al arrancar.

La verificación usa PostgreSQL real con cuentas, asignación, metadatos y extracción ficticios dentro de una transacción. Revierte al finalizar. Sustituye S3 por bytes ficticios en memoria: no valida conectividad S3 ni procesa con IA. La prueba visual siguiente comprueba el original realmente almacenado.

En otra terminal:

```powershell
cd C:\Users\josem\Documents\GitHub\vitalia-health-capstone-prueba\apps\vitalia
flutter pub get
flutter analyze
flutter test test/auth_api_test.dart test/acceso_integrado_test.dart test/documentos_api_test.dart test/paciente_documentos_test.dart test/procesamiento_test.dart test/asignaciones_test.dart test/profesional_test.dart
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

No hay nuevas dependencias. Para Android usa el comando habitual con VITALIA_API_URL=http://10.0.2.2:3000 y la configuración HOST ya preparada; descarga reutiliza el selector nativo existente.

## Flujo visual

1. Asegura con el administrador que tu paciente ficticio tiene relación activa con el profesional.
2. Inicia sesión como profesional. Pulsa Ver exámenes en ese paciente.
3. Pulsa Descargar original sobre el PDF ficticio ya procesado. Abre el archivo descargado y compara el contenido.
4. Pulsa Consultar extracción. Debe mostrar revisión pendiente, cifras, unidades, referencias y fecha conservadas; incidencias y texto de entrada. No hay botones de aprobación o corrección.
5. Verifica el PDF 2: fecha 29-09-2026, Alfa 15,2 g/dL y referencia 14,0–16,0 g/dL; Beta 235.000 /μL y referencia 160.000–460.000 /μL. La unidad extraída puede conservar el espacio inicial observado. No se recorta ni corrige automáticamente.
6. Un documento sin trabajo muestra Procesamiento no solicitado; uno rechazado muestra rechazo sin inventar extracción.
7. Desactiva la relación desde administrador. Al volver a entrar como profesional o actualizar la lista, el paciente desaparece. Una petición de historial, extracción o descarga con la relación inactiva devuelve 404. Las pruebas automatizadas también cubren desactivación durante una descarga.

Puedes volver con la flecha a Mis pacientes. La vista está integrada en el contenedor autenticado: cerrar o vencer la sesión retira también la vista de consulta, sin dejar una ruta separada abierta.

Si deseas probar un administrador y profesional simultáneamente en dos ventanas, inicia sesión en ventanas separadas de la misma aplicación; cada instancia mantiene su propia sesión en memoria. No compartas credenciales ni documentos reales.

## Contrato HTTP

GET /api/professional/patients/{patientId}/documents?limit=20&offset=0 devuelve `{documents: [...]}`. Limit 1–20; offset 0–10000. Solo documentos stored, paginados. Metadatos sin clave S3.

GET /api/professional/patients/{patientId}/documents/{documentId}/extraction devuelve `{document, processing}`. Processing contiene estado, approved false, método, extracción nullable, texto de entrada nullable, incidencias de reading/ocr/ai y metadatos de modelo/prompt nullable. Conserva datos originales; no devuelve respuesta cruda del modelo ni failure_code interno. No se admiten parámetros extra.

GET /api/professional/patients/{patientId}/documents/{documentId}/file entrega el archivo como attachment y nosniff, nunca incrustado. Comprueba clave esperada, firma, tipo y tamaño máximo 10 MiB. La lectura S3 utiliza el adaptador acotado existente. Se limitan a dos trabajos de descarga simultáneos en este router; saturación responde 503.

Todas requieren sesión y rol profesional, con Cache-Control: no-store. Sin sesión: 401; otro rol: 403; asignación ausente/inactiva, paciente/documento ajeno/no disponible o ID inválido: 404; entrada inválida: 400; fallos inesperados: 500 genérico. Solo GET: no se habilita escritura ni aprobación.

## Autorización y auditoría

Las consultas bloquean la relación con FOR SHARE durante la transacción de autorización, lectura y auditoría. Para descarga se autoriza primero, se lee S3 sin mantener una transacción y se vuelve a autorizar antes de registrar y entregar. Una relación desactivada durante la lectura impide devolver el archivo. Fallos de auditoría impiden declarar éxito.

Migración 008 agrega vitalia_professional_access_audit: profesional, paciente, asignación, documento/procesamiento cuando corresponde, acción y fecha. Las acciones son list, view_extraction y download. Registra consultas autorizadas y entrega de descarga desde el servidor; no certifica que el usuario guardó o leyó el archivo en su dispositivo. Intentos denegados no generan eventos exitosos.

La revocación afecta solicitudes posteriores. Una pantalla ya consultada permanece hasta actualizar, cerrar consulta o salir; al refrescar se descarta información previa. Un archivo ya descargado permanece en el dispositivo. No se presenta revocación como borrado remoto.

Los avisos de la lectura directa pueden señalar páginas que necesitaron OCR aunque el OCR posterior haya obtenido texto. Ninguna ausencia de incidencias garantiza exactitud. El original conserva autoridad para el cotejo profesional.

## Verificación

Compilación TypeScript y 246 pruebas backend aprobadas en 31 suites. Pruebas Flutter añadidas, pendientes en Windows por ausencia de SDK en el entorno de implementación. Pendientes: migración/verificación PostgreSQL local y prueba visual con S3 real. La futura revisión debe guardar correcciones separadas sin sobrescribir la extracción original.
