# Errores y límites observados en las evidencias

**Corte:** 2026-11-11, commit `15741b45915ae893c28aa57d80d90171f278db79`, run `42950144149`.

## Resultado final de esta ejecución

- **Errores finales de Jest:** 0. **Flutter general:** 199 aprobadas, 2 omitidas. **Flutter SIL específico:** 2 aprobadas. **Jobs CI:** 2 `success`.
- La salida incluye avisos `DeprecationWarning: url.parse()` de dependencias; registrar la deuda técnica, sin clasificarlo como fallo de prueba.
- La salida Jest contiene eventos como `exam_assistant_failure` y `document_extraction_failure` disparados por pruebas de **rutas de error controladas**. No tratarlos automáticamente como caída real del sistema: la suite terminó completamente aprobada.
- No se adjuntan logs completos sin revisión: podrían contener datos operacionales del runner o fixtures; se conservan los originales en GitHub Actions.

## Ejecuciones fallidas anteriores: historia, no estado final

| Run | SHA/alcance | Resultado | Observación |
|---|---|---|---|
| [42949368120](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42949368120) | Rama temporal del asistente, revisión previa | `failure` | Incompatibilidad de comportamiento con tests del modo DEMO; corregida en PR #26 |
| [42949619043](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42949619043) | Corrección del asistente | `success` | Validación de regresión aprobada |
| [42950144149](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149) | Commit final del corte | `success` | Fuente principal de resultados actuales |

La existencia de runs fallidos históricos no contradice el run final exitoso; documentar la secuencia evita ocultar regresiones y correcciones.

## Gaps que siguen sin validación suficiente

1. **Documentos escaneados:** la batería OCR local no demuestra exactitud y cobertura universal de la recepción principal; una prueba de escaneo sin texto debe producir rechazo controlado en vez de datos inventados.
2. **Historia clínica real:** no se probaron pacientes reales, consentimiento, trámites regulatorios ni autorización clínica de profesionales reales.
3. **PostgreSQL:** `../E07_privilegios.txt` muestra en otra ejecución un rol con `rolsuper=true` y otros privilegios. Hace falta revisión del rol realmente desplegado y principio de mínimo privilegio. **No ejecutar remediaciones ni exhibir secretos sólo para obtener capturas.**
4. **Tailscale externo:** CI valida Nginx en loopback, no la conexión desde equipos externos ni el bloqueo de SMB/RDP mediante grants. Se requiere prueba de otro equipo con evidencia redaccionada.
5. **Calidad del modelo local:** tests de notas verificadas/errores del asistente no cuantifican precisión clínica, generalización lingüística ni disponibilidad real de Ollama bajo carga.
6. **Comparación longitudinal:** implementada con reglas de comparabilidad; no demostrada su robustez con grandes series o todas las variantes del PDF.
7. **Automatización del correo:** no implementada; la invitación requiere entrega fuera de Vitalia.
8. **Accesibilidad/rendimiento/continuidad:** no se hallaron pruebas de carga ni auditoría de accesibilidad integral en la ejecución citada.

## Reproducibilidad segura

- **Jest y TypeScript**: `cd backend && npm ci && npm run check && npm test`.
- **Flutter UI**: `cd apps/vitalia && flutter pub get && flutter test`.
- **Retorno a login SIL**: `flutter test --dart-define=VITALIA_SIL_MAIN_MODE=true test/activar_paciente_retorno_login_test.dart`.
- **Integración API + PostgreSQL + Edge**: reproducir mediante [workflow de GitHub Actions](../../../.github/workflows/sil-main-integration.yml) que crea PostgreSQL **aislado y desechable**, no directamente sobre el PostgreSQL de Beowulf. El guion de recorrido es `backend/test/sil-main-journey.cjs` y debe ejecutarse sólo bajo sus comprobaciones de entorno aislado.
- **Capturas**: descargar el artefacto `vitalia-sil-edge` de la ejecución indicada; no recrear manualmente una captura para presentarla como CI.
