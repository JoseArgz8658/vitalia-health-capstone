# Consulta de revisión aprobada por el paciente

## Alcance
GET /api/documents/:id/review requiere sesión de paciente. PostgreSQL comprueba documento propio con estado stored antes de consultar una revisión aprobada, filtrando nuevamente por patient_id. Responde {review:null} mientras no haya aprobación. Una copia aprobada contiene únicamente extraction, observations, reviewedAt y approved:true. No entrega extracción original, texto OCR, modelo, claves S3 ni datos de acceso del profesional.

El paciente consulta sus resultados sin editar ni aprobar. La revisión permanece accesible para el paciente si después se desactiva la asignación del profesional: el historial aprobado se conserva. Los permisos de consulta del profesional siguen dependiendo de la asignación activa.

## Instalación y comprobación (PowerShell)
Desde la raíz, detener backend y Flutter con Ctrl+C y ejecutar:

```powershell
git fetch origin
git switch --track origin/fase-5/consulta-revision-paciente
cd backend
npm test
node --env-file=.env dist/database/verify-professional-reviews.js
$LASTEXITCODE
npm start
```

No hay migración nueva ni dependencias nuevas. Requiere la migración 009 aplicada en la fase anterior. El verificador usa datos ficticios dentro de una transacción y los revierte; no llama a S3 ni Ollama.

En otra terminal:

```powershell
cd C:\Users\josem\Documents\GitHub\vitalia-health-capstone-prueba\apps\vitalia
flutter pub get
flutter analyze
flutter test test/auth_api_test.dart test/acceso_integrado_test.dart test/documentos_api_test.dart test/paciente_documentos_test.dart test/procesamiento_test.dart test/asignaciones_test.dart test/profesional_test.dart test/revision_profesional_test.dart test/revision_paciente_test.dart
flutter run -d edge --web-hostname localhost --web-port 5173 --dart-define=VITALIA_API_URL=http://127.0.0.1:3000
```

Con la cuenta del paciente, abrir el historial y elegir Ver resultados revisados en el documento ficticio aprobado anteriormente. Comparar cifras, fecha y observaciones con la copia aprobada por el profesional. En uno todavía no revisado se muestra que no existe revisión aprobada. Un null se muestra como No disponible, sin convertirlo en cero ni completar datos.

## Comportamiento y límites
La interfaz limpia los resultados anteriores antes de una consulta y ante errores; 401 cierra sesión. La actualización del estado desmonta el panel anterior. GET es la única operación del paciente sobre esta ruta. Cache-Control:no-store; rol incorrecto 403, documento ajeno/inexistente/no almacenado 404, ausencia de sesión 401. No se aceptan parámetros de consulta.

La fecha de revisión se muestra en la zona local del dispositivo. Las unidades y cifras no se normalizan. La aprobación se refiere al cotejo de datos, no a un diagnóstico ni a indicaciones de tratamiento. Todavía no se genera explicación IA. Rediseño visual general aplazado a petición del usuario.
