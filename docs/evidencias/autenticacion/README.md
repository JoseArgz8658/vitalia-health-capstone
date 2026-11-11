# Evidencia: autenticación, roles y administración

**IDs de matriz:** F01, F02. **Estado:** implementadas y verificadas en escenarios automatizados.  
**Versión:** `15741b45915ae893c28aa57d80d90171f278db79`; **ejecución:** [42950144149](https://github.com/JoseArgz8658/vitalia-health-capstone/actions/runs/42950144149), 2026-11-11 (UTC), `success`.

## Pruebas y afirmaciones cubiertas

| Archivo | Caso verificado | Resultado |
|---|---|---|
| [`sil-main-api.test.cjs`](../../../backend/test/sil-main-api.test.cjs) | Sin MAIN_MODE no hay rutas; rutas principales rechazan anónimos | Jest aprobado |
| El mismo | Paciente no crea laboratorios ni órdenes ajenas | Jest aprobado |
| El mismo | Sólo administrador habilita laboratorios y personal; lista operadores filtrada | Jest aprobado |
| El mismo | Control de concesión/revocación del permiso de revisión por laboratorio | Jest aprobado |
| [`auth-router.test.cjs`](../../../backend/test/auth-router.test.cjs) | Inicio de sesión y restricciones API generales | Jest aprobado |
| [`modos_acceso_test.dart`](../../../apps/vitalia/test/modos_acceso_test.dart) | Accesos profesionales/paciente separados sin conceder roles en el selector UI | Flutter aprobado |
| [`sil_principal_page_test.dart`](../../../apps/vitalia/test/sil_principal_page_test.dart) | Administración de personal y permiso por botón | Flutter aprobado |

**Ejecución:** Job backend `130292268131`, job Flutter `130292267808`; ambos `success`.

**Límites:** el control de permisos del frontend no sustituye el control del backend. Las pruebas funcionales no certifican política de contraseñas institucional real, pentest ni seguridad completa del despliegue. Mantener roles y permisos como requerimientos cubiertos **en los escenarios de prueba**, no como certificación normativa.
