# Bandeja profesional por examen — CAM-098

Preparé consulta, contacto, descarga e inicio de atención para el responsable elegido. Mantengo la extracción pendiente hasta el recorrido integrado con revisión. (José Aránguiz)

## Aplicación local

1. Actualizo fase-7/03-atencion-examen y ejecuto npm test desde backend: espero 763 pruebas en 56 suites.
2. Desde apps/vitalia ejecuto flutter analyze y flutter test: espero 140 pruebas. Su ejecución está pendiente en Windows.
3. Detengo el backend y guardo vitalia_dev_antes_022.
4. Como postgres, con las variables temporales de conexión restauradas al terminar, ejecuto dist/database/migrate-care-inbox.js y dist/database/verify-care-inbox.js. Espero migración aplicada y 52 comprobaciones correctas con datos sintéticos revertidos.
5. En Query Tool de pgAdmin, como postgres en vitalia_dev, ejecuto todo backend/database/permissions/care-inbox-app.sql. Espero COMMIT; compruebo 48 tablas y 22 migraciones.
6. Reinicio backend y Flutter. No inicio la API nueva antes de aplicar 022 y sus permisos.

No modifico .env, no almaceno credenciales administrativas y no vuelvo a cargar un examen real para esta prueba. Puedo utilizar el examen ficticio ya guardado en CAM-097. (José Aránguiz)

## Recorrido

Ingreso en modo profesional con la cuenta que el paciente seleccionó para ese examen. Abro Ver mis atenciones en el espacio profesional y compruebo examen, paciente, clínica, sucursal, especialidad y estado Pendiente de iniciar. No necesito una asignación general de paciente para ver una atención por examen. (José Aránguiz)

Abro la atención y compruebo el contacto confirmado: teléfono, correo, domicilio y zona de consulta separados. Descargo el documento ficticio y compruebo el archivo guardado. Pulso Comenzar atención, verifico el estado En atención y vuelvo a abrir la bandeja para confirmar que persista. Esta acción no procesa el examen ni aprueba resultados. (José Aránguiz)

Pruebo con otra cuenta profesional o jefatura no elegida: el examen no debe aparecer ni poder abrirse por conocer su identificador. El administrador no recibe esta bandeja. Si se suspende una pertenencia o pierde validez la credencial, la atención deja de estar disponible para ese acceso; no se reasigna automáticamente. Evito suspender al único jefe o alterar credenciales reales para una prueba. (José Aránguiz)

La extracción y revisión por atención, derivaciones y segundas opiniones siguen pendientes. Solo después de completar y validar esos incrementos prepararé el cierre y la integración con el repositorio oficial. (José Aránguiz)
