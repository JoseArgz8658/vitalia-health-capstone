# Evidencia: solicitudes médicas PDF, extracción y órdenes

**IDs:** F05, F06, F07, F08. **Versión:** `15741b45915ae893c28aa57d80d90171f278db79`. **Run:** [42950144149](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149).

## Pruebas verificadas

| Caso | Archivo | Resultado |
|---|---|---|
| Prelectura de solicitud: campos y prestaciones sugeridos sin escritura prematura | [`sil-medical-request-intake.test.cjs`](../../../backend/test/sil-medical-request-intake.test.cjs) | Jest aprobado |
| Cotejo paciente, fecha y profesional; rechaza RUT/identidades incompatibles | Mismo archivo | Jest aprobado |
| Documento duplicado no crea segunda orden, transacción revertida | Mismo archivo | Jest aprobado |
| Escaneo sin texto no autoriza crear orden sin OCR | Mismo archivo | Jest aprobado (rechazo seguro) |
| Derivación pendiente descargable y recuperable | [`sil-main-journey.cjs`](../../../backend/test/sil-main-journey.cjs) | Integración `success` |
| Alta y vinculación de orden a cuenta activada | Mismo archivo | Integración `success` |
| UI sugiere fecha del PDF u hoy cuando falta; ID de solicitud es automático | [`sil_principal_page_test.dart`](../../../apps/vitalia/test/sil_principal_page_test.dart) | Flutter aprobado |
| Contenedores administrativos requeridos y restricción de resultados antes de recepción | [`sil-main-journey.cjs`](../../../backend/test/sil-main-journey.cjs) | Integración `success` |
| Pruebas unitarias de OCR local | [`ocr.test.cjs`](../../../backend/test/ocr.test.cjs) | Jest aprobado |

**Interpretación:** recepción/derivación/orden con PDF textual sintético = **implementada y verificada**. Cobertura de **escaneos difíciles y formatos múltiples** = **parcial**, sin métricas de precisión por campo ni batería de documentos representativos en esta ejecución.

**Exclusión inicial del alcance:** procesamiento físico de muestras, cadena de custodia completa e interfases con analizadores. Los tres contenedores son registros administrativos de prueba, no mediciones de equipamiento.
