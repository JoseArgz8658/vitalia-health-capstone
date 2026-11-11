# Registro de pruebas automatizadas y ejecuciones verificadas

**Objeto:** documentar resultados obtenidos de registros reales y existentes. No se alteró el código funcional ni se ejecutaron pruebas contra los datos de Beowulf para crear este expediente.

## Ejecución principal del corte

- **Workflow:** `SIL principal - pruebas de integracion` ([YAML](../../../.github/workflows/sil-main-integration.yml)).
- **Run ID:** `42950144149` — [abrir en GitHub Actions](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149).
- **Fecha inicio:** `2026-11-11T03:03:19Z`; **finalización:** `2026-11-11T03:08:05Z`.
- **Rama/commit de código probado:** `feat/sil-integracion-vitalia-principal` / `15741b45915ae893c28aa57d80d90171f278db79`.
- **Resultado global:** `success` (2 jobs completados).
- **Ejecución repetida del mismo SHA:** [`42950137390`](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950137390), también `success`. No sumar los resultados repetidos como nuevas funcionalidades.

| Componente | Job ID | Comandos o escenario | Resultado tomado del log |
|---|---|---|---|
| Backend | `130292268131` | `npm ci`, `npm run check`, `npm test` | **72/72 suites y 970/970 tests Jest; 0 fallos finales** |
| Flutter genérico | `130292267808` | `flutter pub get`, `flutter analyze`, `flutter test` | **199 passed, 2 skipped**; análisis sin problemas |
| Flutter SIL específico | `130292267808` | `flutter test --dart-define=VITALIA_SIL_MAIN_MODE=true test/activar_paciente_retorno_login_test.dart` | **2 passed** (las dos pruebas omitidas en modo genérico se ejecutaron aquí) |
| Flutter web | `130292267808` | `flutter build web` con API local y luego `VITALIA_API_SAME_ORIGIN=true` | Ambas compilaciones finalizadas correctamente |
| Backend + PostgreSQL temporal + Edge | `130292267808` | `node test/sil-main-journey.cjs` con `VITALIA_ISOLATED_REHEARSAL=YES` | Flujo integrado `success` (ver eventos abajo) |
| Proxy | `130292267808` | `nginx -t` en contenedor desechable | Validación de configuración `success` |
| Evidencia visual | `130292267808` | `actions/upload-artifact@v4` | Artefacto `vitalia-sil-edge` (ID `13823744194`) |

## Fragmentos de salida confirmados (extractos selectivos, sin secretos)

```text
2026-11-11T03:04:15Z Test Suites: 72 passed, 72 total
2026-11-11T03:04:15Z Tests:       970 passed, 970 total
2026-11-11T03:04:15Z Snapshots:   0 total
2026-11-11T03:05:03Z Flutter: 199 tests passed, 2 skipped.
2026-11-11T03:05:14Z Flutter SIL específico: 2 tests passed.
2026-11-11T03:06:47Z API: muestras, resultados por analito, devolución, corrección y aprobación verificados.
2026-11-11T03:06:49Z API: derivación pendiente recuperada, activación y orden atómica aprobadas.
2026-11-11T03:06:49Z API y PostgreSQL: recorrido con credenciales y sesiones reales aprobado.
2026-11-11T03:07:17Z Microsoft Edge: el paciente descargó el informe publicado desde la estación.
```

Los textos anteriores son **extractos normalizados de la salida original** (se omitieron prefijos del runner y datos innecesarios); no sustituyen el [log original](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149).

## Recorridos respaldados por código y log

- [`backend/test/sil-main-api.test.cjs`](../../../backend/test/sil-main-api.test.cjs): bloqueos por rol, administración, controles de publicaciones y aislamiento de pacientes.
- [`backend/test/sil-main-journey.cjs`](../../../backend/test/sil-main-journey.cjs): ensayo aislado con sesión real, derivación PDF, orden y muestras, propuestas de valores, resultados, revisión, publicación y descarga desde Edge.
- [`backend/test/sil-results-file-preview.test.cjs`](../../../backend/test/sil-results-file-preview.test.cjs): propuestas sin persistencia, unidades, identidad y fallas de IA.
- [`backend/test/sil-patient-education.test.cjs`](../../../backend/test/sil-patient-education.test.cjs): biblioteca de 11 analitos, aislamiento y preguntas numéricas no inventadas.
- [`backend/test/sil-patient-report-overview.test.cjs`](../../../backend/test/sil-patient-report-overview.test.cjs): cifras comparables entre informes publicados.
- [`apps/vitalia/test/sil_principal_page_test.dart`](../../../apps/vitalia/test/sil_principal_page_test.dart): UX de recepción, permisos y búsqueda de pacientes/órdenes.
- [`apps/vitalia/test/activar_paciente_retorno_login_test.dart`](../../../apps/vitalia/test/activar_paciente_retorno_login_test.dart): regreso a ingreso de contraseña tras la activación.

## Capturas

Tres capturas producidas por la prueba Edge fueron verificadas como contenido real del ZIP de Actions. Están indexadas con nombre exacto, resolución, fecha, ID y enlace en [capturas_actions.md](../integracion/capturas_actions.md).

## Relación con documento 2.2

Para requerimientos de software, citar: ID Fxx de CSV + prueba concreta + run ID + fecha/commit. Para requerimientos que no están probados, no basta citar el número total de 970 pruebas. Para 2.3, adjuntar exclusiones y la lista priorizada de brechas del [informe funcional](../informe_estado_funcional.md).
