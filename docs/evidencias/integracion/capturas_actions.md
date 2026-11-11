# Capturas reales de interfaz del SIL principal

**Origen verificable:** artefacto **`vitalia-sil-edge`** de [GitHub Actions run 42950144149](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149).  
**Artifact ID:** `13823744194`  
**Creado (UTC):** `2026-11-11T03:08:00Z`. **Expira:** `2027-02-09T03:03:20Z` (según metadatos de Actions).  
**Commit:** `15741b45915ae893c28aa57d80d90171f278db79`.  
**SHA-256 declarado del ZIP por GitHub:** `5cd2065f5e552b2a421aa9a2e29a6fdf817997ee48256bb214eabae8cf54beed`.

Las imágenes fueron generadas por Playwright/Edge en [`backend/test/sil-main-journey.cjs`](../../../backend/test/sil-main-journey.cjs). Se inspeccionó el ZIP real y se comprobaron estos archivos:

| Archivo original en el ZIP | Resolución | Evidencia visual |
|---|---:|---|
| `operador-escritorio.png` | 1440 × 1150 | Panel del operador, órdenes y estados de informes del laboratorio sintético |
| `recepcion-escritorio.png` | 1440 × 1150 | Pantalla de recepción de solicitudes en escritorio |
| `recepcion-movil.png` | 390 × 844 | Adaptación de la recepción a dispositivo móvil |

**Obtención:** abrir [el run](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149), sección **Artifacts**, descargar `vitalia-sil-edge` y extraer sus PNG. Requiere autorización GitHub al repositorio. La acción `actions/upload-artifact@v4` terminó `success`.

**Interpretación:** documentan **UI en CI con datos sintéticos**; no constituyen prueba de que una persona real recibió atención ni de publicación desde Beowulf. La descarga del informe del paciente se acredita mediante el **log** de Playwright/Edge, no mediante una captura de su portal: la ejecución conservada no incluye PNG del portal del paciente.

**Retención:** como el artifact tiene fecha de expiración, es recomendable descargarlo y archivarlo como anexo institucional con acceso restringido. No se ha añadido un PNG binario duplicado en este PR: las capturas auténticas permanecen en GitHub Actions, y este índice las vincula de forma verificable. Nunca sustituirlas por una recreación gráfica sin identificarla claramente.
