# Integración — flujo extremo a extremo (E2E)

**Fuente:** [run 42950144149](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149) y guion `backend/test/sil-main-journey.cjs`. La instancia de ensayo usa PostgreSQL temporal aislado, cuentas/órdenes sintéticas y Microsoft Edge automatizado.

## Secuencia cubierta

1. Montaje del modo SIL principal y pruebas de permisos por API.
2. Identificación de datos sugeridos en derivación PDF; cotejo con paciente sintético.
3. Almacenamiento de derivación pendiente antes de crear cuenta/orden.
4. Emisión de invitación y activación/recuperación del acceso de un solo uso.
5. Creación de orden y prestaciones mediante operación atómica.
6. Registro administrativo de muestras/contendedores.
7. Vista previa de extracción de resultados; validación de identidad y unidades; devolución, corrección y aprobación de analitos.
8. Adjuntar PDF autorizado externamente (como **simulación**) y revisar/confirmar para publicarlo.
9. Consulta/descarga por el paciente autenticado y aislamiento de recursos.
10. Capturas de escritorio y móvil del operador/recepción; control `nginx -t` y build `VITALIA_API_SAME_ORIGIN=true`.

## Evidencias

- [Registro de ejecución](../pruebas/registro_ejecuciones.md), con Job IDs, resultados y extractos.
- [Capturas de Edge](./capturas_actions.md), artefacto de GitHub Actions `13823744194`.
- [Matriz de trazabilidad](../matriz_evidencias.csv): F01–F23.
- [Código de recorrido](../../../backend/test/sil-main-journey.cjs).

## Límites

La ejecución no verifica que **Tailscale** permita únicamente HTTPS y deniegue SMB/RDP desde una estación externa; tampoco verifica un servidor permanentemente disponible 24/7. No envía correos reales. La autorización externa es representada por datos sintéticos y confirmación humana simulada. Las muestras se **registran**, no son procesadas físicamente.

**Política de datos:** capturas y logs de CI son sintéticos. No incluir identificadores/credenciales del Beowulf real ni realizar E2E destructivo contra su base PostgreSQL.
