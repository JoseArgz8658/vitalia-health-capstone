# Validación integrada de los tres roles — SIL principal

**Proyecto:** Vitalia Health (SIL postanalítico)  
**Fecha de ejecución:** 21 de noviembre de 2026 (Chile; GitHub Actions registra fechas UTC).  
**Versión base:** `develop` en `3e9e6c8e93c0ad7b885866f082568a6e0251d7a2`, con los PR #32 a #36 consolidados.  
**Intervención:** [PR #37](https://github.com/JoseArgz8658/vitalia-health-capstone/pull/37).  
**Ejecución automatizada:** [GitHub Actions — run 44977312298](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/44977312298).  
**Compilación Android:** [GitHub Actions — run 44977312356](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/44977312356).

## Entorno y alcance

Se usa PostgreSQL 16 temporal, aislado en loopback del runner, migraciones `012–032` y `038–041`, API Express/TypeScript, frontend Flutter web y Microsoft Edge automatizado con Playwright. Cuentas, pacientes, PDFs, laboratorios y permisos son **sintéticos**, con correos `@example.invalid`.

No se usa el PostgreSQL del equipo, el servidor local, Docker Desktop del equipo ni Tailscale. Tampoco se simulan diagnósticos ni autorización médica real: las aprobaciones externas se representan con confirmaciones ficticias.

## Matriz de escenarios y criterios verificables

| ID | Rol | Comprobación automatizada | Resultado esperado |
|---|---|---|---|
| VR-ADM-01 | Administrador | Autenticación en `/#/administracion`, laboratorios sintéticos por API y menú superior | Se autentica con rol administrador, obtiene dos laboratorios y no ve funciones clínicas |
| VR-ADM-02 | Administrador | Consulta de personal del laboratorio seleccionado | `GET /labs/:id/staff` responde 200 y muestra dos operadores sin credenciales |
| VR-ADM-03 | Administrador | Revocar y restituir permiso de revisión | Operaciones 200, mismo operador, permiso final restituido; sin cambiar la base de ensayo fuera del recorrido |
| VR-ADM-04 | Administrador | Actividad administrativa y aislamiento clínico | Muestra recuento administrativo de personal y permisos, sin solicitar órdenes clínicas ni habilitar descarga de PDF |
| VR-OPE-01 | Operador | Barra superior y recepción en escritorio y móvil | Navegación accesible, recepción disponible, lectura PDF bloqueada sin archivo |
| VR-OPE-02 | Operador | Órdenes, PDF de resultados, cotejo humano y auditoría | Consulta y creación/registro funcionales, con respuesta HTTP y datos sintéticos |
| VR-OPE-03 | Operador | Adjuntar, descargar, revisar y publicar informe | PDF original revisado, confirmaciones exigidas y publicación con HTTP 201 |
| VR-PAC-01 | Paciente | Acceso al portal móvil y visibilidad restringida | Consulta Mis informes sin acciones de operador |
| VR-PAC-02 | Paciente | Ayuda y Mi perfil | Navegación accesible y apertura/cierre de diálogos |
| VR-PAC-03 | Paciente | Descarga de informe publicado | Archivo descargado coincide byte a byte con PDF sintético autorizado |
| VR-SEG-01 | Transversal | Roles, laboratorio y estado de informe por API | Acceso denegado cuando corresponde y aislamiento entre laboratorios |
| VR-SEG-02 | Transversal | Recuperación y credenciales | Clave anterior no autentica, nueva sí; límite de login sin alteración |
| VR-CI-01 | Transversal | Tests Jest, Flutter, configuración SIL, build web y APK | Sin fallas de automatización en el commit evaluado |

## Corrección detectada durante el ensayo

La carga del administrador intentaba solicitar `GET /labs/:id/orders`, ruta exclusiva del operador, lo que provocaba HTTP 403 e interrumpía la consulta posterior del personal. Se corrigió `_loadLabs` y `_selectLab` para consultar datos de órdenes y derivaciones **únicamente como operador**, y personal **únicamente como administrador**. La sección Actividad administrativa presenta ahora un resumen de personal y permisos, no información clínica. Se añadió una regresión Flutter que fuerza HTTP 403 sobre la ruta de órdenes y verifica que el administrador continúe funcionando sin invocarla.

La suite también reveló que el ensayo consumía los intentos de autenticación de su propia IP. Se sustituyeron comprobaciones HTTP redundantes de la contraseña recuperada por llamadas directas al mismo servicio de credenciales del backend. **No se modificó el límite de producción** (10 intentos por IP en 15 minutos).

## Evidencias técnicas

- Código de recorrido: `backend/test/sil-main-journey.cjs`.
- Regresión de permisos y carga de administrador: `apps/vitalia/test/sil_principal_page_test.dart`.
- Configuración de CI: `.github/workflows/sil-main-integration.yml`.
- Capturas de Edge en artefacto GitHub Actions `vitalia-sil-edge`, generado por la ejecución cuando el recorrido llega a las pantallas.
- Las URL de GitHub Actions enlazadas arriba son la fuente primaria del **resultado final**, que debe consultarse antes de afirmar que todos los escenarios aprobaron.

## Límites y validaciones posteriores

Las pruebas automatizadas no equivalen a una aceptación de usuario real. Permanece pendiente la evaluación visual/usabilidad en dispositivos y navegadores reales, la verificación de seguridad del servidor PostgreSQL local, permisos de infraestructura, configuración vigente de Tailscale y acceso remoto, y cualquier auditoría normativa antes de procesar información clínica real.

**Criterio de cierre:** los jobs de integración del PR #37 deben terminar en `success`; resultados pendientes o fallidos no se consideran aprobados. La fusión a `develop` se hará solamente tras ese control.
