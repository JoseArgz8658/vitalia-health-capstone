# Evidencia: resultados, autorización, publicación e historial

**IDs:** F09–F14, F20. **Fecha:** 2026-11-11 (UTC). **Versión:** `15741b45915ae893c28aa57d80d90171f278db79`. **Run:** [42950144149](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149).

## Pruebas y resultados

| Escenario | Fuente | Resultado |
|---|---|---|
| Registro de resultados por analito y estado pendiente | [`sil-main-journey.cjs`](../../../backend/test/sil-main-journey.cjs) | Integración `success` |
| Devolución, corrección y aprobación de valores sintéticos | Mismo | Integración `success` |
| Publicación exige permiso y confirmación de revisión | [`sil-main-api.test.cjs`](../../../backend/test/sil-main-api.test.cjs) y E2E | Jest + Edge aprobados |
| Adjuntar PDF a orden declarando autorización externa | E2E + [capturas de operador](../integracion/capturas_actions.md) | Integración `success` |
| Descarga PDF por paciente dueño y publicado | E2E, log de Edge | Integración `success` |
| Historial de orden separado por laboratorio | E2E | Integración `success` |
| Comparación sólo de valores comparables en PDF publicado | [`sil-patient-report-overview.test.cjs`](../../../backend/test/sil-patient-report-overview.test.cjs) | Jest aprobado |
| UI de comparación requiere dos informes publicados | [`paciente_portal_sil_test.dart`](../../../apps/vitalia/test/paciente_portal_sil_test.dart) | Flutter aprobado |

**Clasificación:** entrega/publicación de informe y la descarga privada están **implementadas y verificadas** con datos sintéticos. Comparación histórica **parcial** (requiere dos o más documentos comparables); autorización clínica digital **pendiente**, porque hoy se adjunta un documento declarado autorizado externamente, sin firma verificable dentro del SIL.

**No se evidencia:** firma electrónica real, lectura directa del analizador, diagnóstico automático o valoración médica de la coherencia de los analitos; no presentarlos como completados.
