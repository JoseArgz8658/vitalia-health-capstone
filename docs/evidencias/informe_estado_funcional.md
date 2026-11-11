# Informe del estado funcional real de Vitalia Health

**Uso previsto:** apoyo verificable de 2.2 Requerimientos de Software y 2.3 Gestión del Alcance.  
**Fecha de corte:** 11-11-2026 (UTC). **Versión auditada:** `15741b45915ae893c28aa57d80d90171f278db79`.  
**Fuentes:** [GitHub Actions #42950144149](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149), pruebas versionadas y capturas publicadas como artefacto de CI.

## Resumen ejecutivo

**El flujo postanalítico principal está implementado y fue recorrido en pruebas con datos sintéticos:** sesión por rol, administración institucional, recepción de solicitud PDF, derivación pendiente, invitación y activación de paciente, asociación de la solicitud con una orden, recepción administrativa de contenedores, carga/cotejo/aprobación de resultados, adjunto de informe con declaración de autorización externa, revisión/publicación y acceso del paciente al informe publicado.

El **workflow completo** terminó con éxito para la versión citada; también pasaron **970/970 pruebas Jest (72 suites)**, **199 Flutter**, **2 Flutter específicas del modo SIL** y la integración Edge/PostgreSQL. Esto **no** significa que la plataforma esté lista para manejar datos clínicos reales en producción.

## Estado por funcionalidad

| ID | Funcionalidad / alcance efectivamente probado | Clasificación | Reserva o limitación |
|---|---|---|---|
| F01 | Autenticación, sesiones, segregación por rol y rutas protegidas | **Implementada y verificada** | Pruebas funcionales, no pentest externo |
| F02 | Alta de laboratorios, personal operador y permisos de revisión | **Implementada y verificada** | Escenarios sintéticos y permisos previstos, no operación productiva |
| F03 | Invitación, activación y recuperación del acceso de pacientes | **Implementada y verificada** | Entrega del código de invitación es manual |
| F04 | Cotejo de identidad asociado a derivación | **Implementada parcialmente** | Se exige confirmación humana, no verificación de identidad contra registro oficial |
| F05 | Recepción de PDF legible y extracción/sugerencia de datos y prestaciones | **Implementada y verificada** | Verificada con archivos sintéticos soportados |
| F06 | Procesamiento de documentos escaneados/formatos arbitrarios en recepción SIL | **Implementada parcialmente** | El lector contempla estados sin texto; no hay prueba de cobertura de OCR para todos los escaneos |
| F07 | Persistencia de derivación pendiente, recuperación y registro atómico de orden | **Implementada y verificada** | El operador debe cotejar datos sugeridos |
| F08 | Registro administrativo de contenedores requeridos por orden | **Implementada y verificada** | No comprende toma/analítica física de muestra |
| F09 | Registro, devolución, corrección y aprobación de analitos | **Implementada y verificada** | Revisión de resultados sintéticos; no sustituye validación profesional externa |
| F10 | Adjuntar informe PDF con declaración de autorización externa | **Implementada y verificada** | No valida criptográficamente la firma ni integra autorización clínica externa |
| F11 | Bandeja de revisión, validación y publicación del informe | **Implementada y verificada** | Se exige confirmación del operador autorizado |
| F12 | Consulta y descarga del informe publicado por el paciente autenticado | **Implementada y verificada** | Sólo informes publicados pertenecientes a la cuenta; probado en Edge |
| F13 | Historial administrativo y auditoría del ciclo de la orden | **Implementada y verificada** | Alcance auditado de eventos específicos; no revisión exhaustiva de logs |
| F14 | Comparación longitudinal de resultados | **Implementada parcialmente** | Estadísticas sólo para analitos/unidades/laboratorio comparables y al menos dos informes |
| F15 | Vista previa de extracción numérica desde PDF | **Implementada parcialmente** | No persiste propuestas automáticamente; unidad dudosa, identidad ambigua y escaneos requieren intervención |
| F16 | Explicaciones educativas de conceptos de los 11 analitos y restricciones temáticas | **Implementada parcialmente** | Notas del catálogo verificadas; calidad de IA generativa en datos/formatos reales no acreditada |
| F17 | Aislamiento de pacientes/laboratorios, permisos y controles de API | **Implementada y verificada** | Cobertura funcional de controles negativos; sin auditoría independiente de seguridad |
| F18 | Endurecimiento de PostgreSQL y mínimo privilegio en Beowulf | **Implementada sin prueba suficiente** | Archivo histórico `E07_privilegios.txt` señala posible exceso de privilegios que debe verificarse |
| F19 | Envío automático de invitaciones/notificaciones por correo | **Pendiente de implementación** | Código de invitación se entrega por canal verificado externo al sistema |
| F20 | Verificación digital de autorización o firma clínica externa | **Pendiente de implementación** | Hoy sólo se registra la referencia y la declaración de autorización |
| F21 | Restricción de Tailscale a HTTPS 443 y aislamiento efectivo de SMB/RDP desde equipo externo | **Implementada sin prueba suficiente** | Política informada, pero sin acta automatizada de prueba remota de puertos |
| F22 | Ensayos de carga, accesibilidad integral y seguridad ofensiva | **Pendiente de implementación** | No están cubiertos por la ejecución CI citada |

**Importante:** F19/F20/F22 son brechas para madurez operativa, **no** un compromiso de incorporarlas todas en la entrega académica. El docente/equipo debe decidir expresamente cuáles son requisitos de 2.2 y cuáles quedan diferidos en 2.3.

## Evidencias verificables del flujo principal

1. **Backend (Jest):** 72 suites / 970 casos aprobados en [run 42950144149, job backend](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149).
2. **Flutter:** 199 casos aprobados; dos casos omitidos intencionalmente en modo genérico y ejecutados después en modo SIL, **2/2 aprobados**.
3. **Integración real en CI:** `backend/test/sil-main-journey.cjs` con PostgreSQL aislado y Microsoft Edge. El log confirma recepción/orden, muestras, resultados revisados, informe publicado y descarga paciente.
4. **Capturas CI:** `operador-escritorio.png`, `recepcion-escritorio.png`, `recepcion-movil.png` dentro del artefacto [vitalia-sil-edge](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149) (ID `13823744194`). Ver [índice de capturas](./integracion/capturas_actions.md).
5. **Seguridad:** `backend/test/sil-main-api.test.cjs` prueba bloqueos anónimos, separación de pacientes, autorización administrativa y aislamiento de laboratorio. La evidencia es funcional y puntual, no una certificación.

## Capacidades que requieren desarrollo adicional o comprobación

| Prioridad para 2.2/2.3 | Capacidad | Decisión sugerida |
|---|---|---|
| Alta | **Cotejo real de identidad** y completitud de ficha | Explicitar validación humana y sus evidencias; dejar verificación externa como futuro |
| Alta | **Consistencia clínica/analítica y validación de informes** | Mantener supervisión profesional, alerta ante incongruencias y trazabilidad; no inferir validez clínica por tener 11 datos cargados |
| Alta | **Autorización externa demostrable** | Definir cómo se verifica al profesional autorizante; firma digital integrada queda pendiente |
| Alta | **Mínimo privilegio de PostgreSQL** | Auditar rol y privilegios actuales, rotar credenciales si procede, documentar remediación; no inferir del archivo histórico |
| Media | **OCR en escaneos de múltiples laboratorios** | Ejecutar batería representativa y medir exactitud por campo; no marcar como resuelto sin medición |
| Media | **Notificación/invitación al paciente** | Definir entrega manual actual y automatización futura con proveedor, presupuesto y consentimiento |
| Media | **Historia y comparación longitudinal** | Probar con dos o más informes sintéticos compatibles/incompatibles y fechas diferentes |
| Media | **Calidad de asistente local** | Evaluar variaciones lingüísticas, exactitud de todos los analitos, cifras/units y manejo de respuestas inseguras |
| Media | **Aislamiento Tailscale desde equipo de José** | Registrar pruebas remotas de 443 permitido y 445/3389 denegados (no desde Beowulf) |
| Baja/futuro | **Rendimiento, accesibilidad y continuidad del host** | Medir carga, recuperación ante fallos y accesibilidad; no declarar 24/7 por tener Tailscale Serve |

## Delimitación de alcance postanalítico

**Dentro del alcance funcional demostrado:** recibir documentos y registrar administrativamente órdenes, muestras declaradas y resultados, gestionar revisión y publicación, y permitir consulta privada/educativa del informe.

**Fuera del alcance inicial declarado:** toma física de muestras, cadena de custodia material completa, conexión automática con analizadores, agenda, facturación y emisión de diagnósticos. Se documentan como **exclusiones**, no como funcionalidades defectuosas.

## Criterios para cerrar formalmente 2.2 y 2.3

- Asociar cada RF de 2.2 con un ID `Fxx` de [matriz_evidencias.csv](./matriz_evidencias.csv).
- Mantener las cuatro clasificaciones y describir cualquier excepción.
- Para «verificada», adjuntar prueba fuente **y** run/commit, no sólo captura.
- Separar pruebas unitarias, integración CI y observaciones manuales de Beowulf.
- No registrar «cumplimiento sanitario», «OCR universal», «IA diagnóstica», «seguridad total» ni «alta disponibilidad 24/7» como completados.
- Si el requerimiento no existe en 2.2 o está excluido por 2.3, indicar «no comprometido» en el alcance en vez de cambiar retrospectivamente la evidencia.

**Conclusión:** Vitalia tiene un recorrido postanalítico integrado que funciona con datos sintéticos y una base amplia de pruebas automatizadas. Las brechas identificadas deben tratarse como restricciones del prototipo o tareas futuras, sin alterar el funcionamiento estable únicamente para presentar el trabajo.
