# Evidencias técnicas — Vitalia Health (documentos 2.2 y 2.3)

**Corte de revisión:** 2026-11-11 (UTC)  
**Código auditado:** `15741b45915ae893c28aa57d80d90171f278db79`  
**Rama de origen:** `feat/sil-integracion-vitalia-principal`  
**Tipo de evidencia:** pruebas automatizadas preexistentes, logs reales de GitHub Actions, artefactos de Edge y revisión de código.  
**Entorno:** CI temporal con datos sintéticos, PostgreSQL aislado y Edge; no es una certificación clínica ni una prueba de producción.

## Índice central para las entregas de Capstone

**[Abrir índice de evidencias Fase 2 con URLs directas y verificadas](./INDICE_EVIDENCIAS_CAPSTONE_FASE2.md)**. Contiene la correspondencia entre documentos 2.2, 2.3, 2.6 y presentación, las pruebas F01–F23, el commit auditado, los jobs de CI y las advertencias sobre artefactos temporales. Consultarlo antes de enlazar una evidencia en Word.

## Entregables

- [Informe de estado funcional](./informe_estado_funcional.md): evaluación conservadora de alcance y brechas de 2.2/2.3.
- [Matriz de trazabilidad CSV](./matriz_evidencias.csv): cada funcionalidad, prueba, ejecución, resultado y clasificación.
- [Registro de ejecuciones](./pruebas/registro_ejecuciones.md): fechas, commit, conteos y enlaces comprobables.
- [Manifiesto de CI en JSON](./pruebas/manifest_ci_42950144149.json): evidencia estructurada para importar a los documentos.
- [Errores, limitaciones y reproducibilidad](./pruebas/errores_y_limitaciones.md).
- [Índice de capturas reales de Edge](./integracion/capturas_actions.md): tres PNG originales disponibles en un artefacto descargable de GitHub Actions.
- Respaldo por módulo: [autenticación](./autenticacion/README.md), [pacientes](./pacientes/README.md), [solicitudes](./solicitudes/README.md), [informes](./informes/README.md), [IA](./IA/README.md), [seguridad](./seguridad/README.md), [pruebas](./pruebas/README.md) e [integración](./integracion/README.md).

## Fuente primaria de verificación

| Fuente | Ejecución | Fecha (UTC) | Resultado |
|---|---|---|---|
| [GitHub Actions - SIL principal](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149) | `42950144149` | 2026-11-11 03:03–03:08 | **SUCCESS** en ambos jobs |
| [GitHub Actions - segunda ejecución mismo SHA](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950137390) | `42950137390` | 2026-11-11 03:03–03:07 | **SUCCESS** en ambos jobs |

**Precaución:** los archivos preexistentes `E01_*` a `E07_*` se conservan como histórico, sin asumir que representan el estado actual. En particular, `E05_pruebas.txt` refleja una batería anterior de 373 pruebas y `E07_privilegios.txt` muestra un rol PostgreSQL con privilegios elevados en una captura antigua; ambos necesitan contextualizarse y no son prueba de la configuración actual de Beowulf.

## Criterio de clasificación

1. **Implementada y verificada:** existe código y evidencia de ejecución satisfactoria del escenario descrito.
2. **Implementada parcialmente:** existe un camino funcional, pero hay capacidades incompletas o límites expresos.
3. **Implementada sin prueba suficiente:** existe código o configuración, pero el control requerido no tiene comprobación suficiente en este corte.
4. **Pendiente de implementación:** no existe un flujo implementado para la capacidad expresamente indicada; distinguir de funciones *fuera del alcance inicial*.

Una ejecución verde certifica **solo los escenarios ejecutados**. No acredita por sí sola desempeño, cumplimiento legal, seguridad de un despliegue real, precisión de OCR en todos los formatos ni validez de decisiones clínicas.

## Seguridad del repositorio de evidencias

No adjuntar PDFs clínicos reales, contraseñas, tokens, archivos `.env`, volúmenes PostgreSQL ni respuestas API con identidad de personas reales. Se referencian los artefactos de CI existentes, que utilizan datos sintéticos. Las capturas se conservan como originales de CI: no se vuelven a fabricar ni se presentan imágenes de una ejecución como si pertenecieran a otra.
