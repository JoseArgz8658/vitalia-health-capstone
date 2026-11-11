# Evidencia: extracción local e IA educativa

**IDs:** F15 y F16. **Versión:** `15741b45915ae893c28aa57d80d90171f278db79`. **Run aprobado:** [42950144149](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149), 2026-11-11 (UTC).

## Evidencias relevantes

| Prueba | Aserción concreta | Resultado |
|---|---|---|
| [`sil-results-file-preview.test.cjs`](../../../backend/test/sil-results-file-preview.test.cjs) | Sugerencias de resultados **no persisten** automáticamente | Jest aprobado |
| Mismo archivo | Identidad contradictoria o unidad ambigua bloquean aplicación de propuesta | Jest aprobado |
| Mismo archivo | Fallo local de IA ofrece ingreso manual en vez de inventar datos | Jest aprobado |
| [`sil-patient-education.test.cjs`](../../../backend/test/sil-patient-education.test.cjs) | Explica **plaquetas** y las notas de los **11 analitos** de la orden publicada | Jest aprobado |
| Mismo archivo | Consulta numérica no fabrica cifras; informes ajenos/no publicados no son accesibles | Jest aprobado |
| [`sil-patient-report-overview.test.cjs`](../../../backend/test/sil-patient-report-overview.test.cjs) | Lee mediciones de PDF íntegro y compara sólo equivalentes | Jest aprobado |
| [`exam-assistant.test.cjs`](../../../backend/test/exam-assistant.test.cjs) | Evaluación de respuestas del asistente y validación de contenido | Jest aprobado |

## Qué NO afirma esta prueba

- Que Ollama responda correctamente a cualquier pregunta libre o bajo carga sostenida.
- Que la biblioteca de conceptos equivale a una validación clínica personalizada.
- Que se verificó una tasa de precisión de OCR para PDFs fotografiados.
- Que se utilizaron datos clínicos reales, o que el modelo produce diagnósticos.
- Que se necesita o se integró Gemini: no se añadió ningún proveedor externo para este expediente.

**Clasificación:** **implementada parcialmente** como capacidad general, con subcasos **verificados** de extracción no persistente, notas educativas y restricciones. La calidad en documentos variados, disponibilidad del modelo local y explicaciones sobre cifras personales requieren evaluación separada.
