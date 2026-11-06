# Credenciales profesionales — ejecución y prueba

Preparé este incremento en `fase-7/03-atencion-examen`, en el repositorio de prueba. Documenté decisiones y límites en [CAM-095](../cambios-codigo/CAM-095-verificacion-credenciales-profesionales.md). (José Aránguiz)

## 1. Código y pruebas

Conservar cambios locales antes de actualizar la rama. Desde backend ejecutar npm test y comprobar salida 0; se esperan 676 pruebas en 53 suites. Desde apps/vitalia ejecutar flutter analyze y flutter test; se esperan 122 pruebas. No dar por comprobada la interfaz únicamente por el análisis de formato Dart.

## 2. Respaldo y migración

Después de aprobar las pruebas, detener la API y guardar un respaldo nuevo, por ejemplo `vitalia_dev_antes_020`. Confirmar que 019 está aplicada. Revisar 020_professional_credentials.sql. La migración no convierte perfiles pendientes en verificados ni crea evidencia para perfiles anteriores.

Desde backend, con credenciales administrativas temporales:

```powershell
$usuarioAnterior = $env:PGUSER
$passwordAnterior = $env:PGPASSWORD
$baseAnterior = $env:PGDATABASE
try {
    $credencial = Get-Credential -UserName postgres -Message "Credenciales administrativas de PostgreSQL local"
    if ($null -eq $credencial) { throw "Operación cancelada." }
    $env:PGUSER = "postgres"
    $env:PGPASSWORD = $credencial.GetNetworkCredential().Password
    $env:PGDATABASE = "vitalia_dev"
    node --env-file=.env dist/database/migrate-professional-credentials.js
    if ($LASTEXITCODE -ne 0) { throw "Falló la migración 020." }
    node --env-file=.env dist/database/verify-professional-credentials.js
    if ($LASTEXITCODE -ne 0) { throw "Falló la verificación de credenciales." }
    node --env-file=.env dist/database/verify-exam-care.js
    if ($LASTEXITCODE -ne 0) { throw "Falló la compatibilidad de atención." }
}
finally {
    $env:PGUSER = $usuarioAnterior
    $env:PGPASSWORD = $passwordAnterior
    $env:PGDATABASE = $baseAnterior
    $credencial = $null
}
```

Mensajes previstos:

```text
Migración de credenciales profesionales aplicada.
Credenciales profesionales: 46 comprobaciones correctas. Datos sintéticos revertidos.
Atención por examen: 54 comprobaciones correctas. Datos sintéticos revertidos.
```

El inventario previsto es 46 tablas y 20 migraciones. No iniciar Compose ni el migrador general antes del respaldo: descubren automáticamente 020.

## 3. Permisos

En pgAdmin, como postgres sobre vitalia_dev, revisar y ejecutar completo `backend/database/permissions/professional-credentials-app.sql`. Esperar COMMIT. Mantener los permisos anteriores y la API usando vitalia_app. No cambiar permanentemente .env a postgres. Reiniciar el backend y Flutter.

## 4. Registro por el jefe

Abrir el equipo de su clínica y pulsar **Credenciales profesionales** sobre una pertenencia. Revisar el estado y registrar la referencia profesional y la referencia institucional de los antecedentes. Guardar.

Comprobar que se muestra pendiente y que el registro no marca verificado. El jefe no debe disponer de **Revisar solicitud** ni poder registrar antecedentes en otra clínica manipulando la URL. La jefatura puede presentar sus propios antecedentes para revisión administrativa; no puede aprobarlos.

Utilizar exclusivamente datos de prueba en las demostraciones. No incluir exámenes, datos de pacientes, contraseñas ni afirmar una verificación real que no se haya realizado.

## 5. Decisión por el administrador

Desde la misma clínica y equipo, abrir las credenciales y pulsar **Revisar solicitud**. Contrastar fuera de la aplicación la referencia y la correspondencia del profesional con la fuente. Elegir explícitamente Verificado o Rechazado, registrar la fuente contrastada, fecha de consulta y fundamento. Marcar la casilla y guardar.

Comprobar:

- Sin elegir resultado, fuente, fundamento o confirmación no se guarda.
- La fecha de consulta no admite días futuros.
- Aparecen estado, responsable, fecha y referencias en el historial.
- El reintento idéntico no duplica solicitudes ni decisiones.
- Una segunda decisión para la misma solicitud se rechaza.
- Si otro administrador cambió la revisión del perfil, se exige actualizar.
- No cambian las contraseñas, roles ni pertenencias ni aparecen exámenes al administrador.

## 6. Multiclínica y continuidad

Si el profesional pertenece a dos clínicas, la verificación es global, pero cada jefe consulta solo las solicitudes de su clínica. No crear solicitudes pendientes duplicadas para la misma persona. Un rechazo documentado retira la elegibilidad del modelo nuevo en todas sus pertenencias; no borra cuentas ni altera automáticamente las asignaciones legadas.

Un perfil antiguo marcado verificado sin evidencia de este módulo requiere una revisión documentada antes de ser elegible para una nueva atención. No modificar directamente los estados para llenar un catálogo.

El próximo incremento conectará catálogo y elección al examen y adaptará lectura y revisión por documento. Esta pantalla no implementa todavía esos menús ni finaliza la fase 7.

(José Aránguiz)
