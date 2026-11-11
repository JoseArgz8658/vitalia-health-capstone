# Evidencia: pacientes, identidad y acceso privado

**IDs:** F03, F04, F19. **Commit:** `15741b45915ae893c28aa57d80d90171f278db79`; [run CI](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149) del 2026-11-11 (UTC).

## Funcionalidades evidenciadas

| Verificación | Prueba | Resultado |
|---|---|---|
| Invitación con código de un solo uso y activación de paciente | [`sil-main-journey.cjs`](../../../backend/test/sil-main-journey.cjs) | E2E `success` |
| Derivación guardada antes de que exista paciente/orden | Mismo guion | E2E `success` |
| Coincidencia de identidad sugerida, rechazo de datos ambiguos y RUT sin rótulo | [`sil-main-referral-identity.test.cjs`](../../../backend/test/sil-main-referral-identity.test.cjs) | Jest aprobado |
| Paciente activado se encuentra en laboratorio sin escribir UUID en UI | [`sil_principal_page_test.dart`](../../../apps/vitalia/test/sil_principal_page_test.dart) | Flutter aprobado |
| Tras activación se puede escribir contraseña sin refrescar | [`activar_paciente_retorno_login_test.dart`](../../../apps/vitalia/test/activar_paciente_retorno_login_test.dart) | 2/2 pruebas SIL aprobadas |
| Portal visualiza informe publicado y conserva aislamiento | [`paciente_portal_sil_test.dart`](../../../apps/vitalia/test/paciente_portal_sil_test.dart) y E2E | Flutter + Edge aprobados |

**Alcance:** activación y consulta **implementadas y verificadas**; verificación de identidad auténtica **parcial**, pues depende de cotejo humano; invitación por email **pendiente**, pues el código se entrega manualmente en un canal externo.

**Restricción:** no almacenar códigos de invitación, sesiones ni contraseñas como evidencia. El caso de Ana María usado en desarrollo es sintético; los informes académicos deben mencionar únicamente el flujo y los IDs de prueba.
