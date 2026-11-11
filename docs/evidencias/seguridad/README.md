# Evidencia: permisos, auditoría, aislamiento y riesgos residuales

**IDs:** F17, F18 y F21. **Commit:** `15741b45915ae893c28aa57d80d90171f278db79`. **Run:** [42950144149](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149), 2026-11-11 (UTC).

## Controles probados (funcionales)

| Control | Fuente | Resultado |
|---|---|---|
| Acceso anónimo rechazado; paciente no crea laboratorios/órdenes ajenas | [`sil-main-api.test.cjs`](../../../backend/test/sil-main-api.test.cjs) | Jest aprobado |
| Sólo administrador crea laboratorio/operador o concede revisión | Mismo archivo | Jest aprobado |
| Listado institucional y consulta de órdenes aislados | Mismo archivo y [`sil-main-journey.cjs`](../../../backend/test/sil-main-journey.cjs) | Jest y E2E aprobados |
| PDF del paciente restringido a documentos publicados de su cuenta | E2E y [`sil-patient-report-overview.test.cjs`](../../../backend/test/sil-patient-report-overview.test.cjs) | Integración/Jest aprobados |
| Eventos de auditoría asociados a orden y laboratorio | E2E | Integración aprobada |
| Configuración de proxy Nginx válida | [workflow](../../../.github/workflows/sil-main-integration.yml) paso `nginx -t` | CI aprobada |

## Hallazgos y acciones necesarias

1. **Privilegios PostgreSQL:** el archivo histórico [`E07_privilegios.txt`](../E07_privilegios.txt) muestra `rolsuper=t`, `rolcreatedb=t`, `rolcreaterole=t` y `rolreplication=t` para un rol de la ejecución antigua. **No puede deducirse** de allí el estado de la instancia actual: ejecutar una verificación *de solo lectura* por administrador autorizado, documentar el resultado redaccionado y revisar el mínimo privilegio. Prioridad alta.
2. **Red Tailscale:** la política informada restringe un dispositivo compartido al puerto HTTPS, pero no hay en este corte evidencia CI que demuestre desde otro equipo las denegaciones de SMB 445/RDP 3389. En la demostración, las pruebas locales del propio host **no** sustituyen a la prueba remota. Clasificar como **implementada sin prueba suficiente**.
3. **CORS, HTTPS y despliegue:** el workflow valida la sintaxis del Nginx y la compilación same-origin, no una auditoría de TLS/infraestructura de Beowulf.
4. **Datos clínicos:** el sistema sólo fue probado con información sintética para este expediente. No declarar adecuación legal/organizacional al uso clínico real.
5. **Seguridad de software:** no se ejecutó pentest, análisis ofensivo ni revisión independiente de dependencias en esta evidencia.

## Evidencia futura propuesta (sin cambiar el sistema)

- Capturar salida **redaccionada** de permisos PostgreSQL y fecha, con administración autorizada.
- Registrar desde PC externa: HTTPS 443 permitido, SMB 445 y RDP 3389 denegados, en el contexto correcto de la política Tailscale y con estado conectado; registrar también que no hay recursos compartidos por fuera de la política.
- Conservar el resultado de `/api/health` sin credenciales, junto con versión y hora, sin exponer equipos ni datos de pacientes en el informe público.

**Conclusión:** RBAC y aislamiento funcional del SIL **verificados en pruebas**; seguridad del despliegue físico, privilegios PostgreSQL y red externa requieren validación adicional.
