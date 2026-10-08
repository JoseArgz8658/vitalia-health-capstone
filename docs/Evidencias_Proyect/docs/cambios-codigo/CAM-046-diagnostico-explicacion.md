# CAM-046 — Diagnóstico de explicación fallida

El usuario confirma superíndices correctos y 67 pruebas Flutter aprobadas; rectifica la sospecha de unidad alterada. No se modifica ninguna unidad.

La explicación reporta servicio no disponible tras una espera. Se separan timeout, transporte/HTTP del modelo, configuración y rechazo de respuesta. El backend registra solo evento, modo, categoría y duración; no registra pregunta, examen, respuesta, identificadores ni mensajes internos.

Esto permite diagnosticar el fallo real antes de cambiar límites o comportamiento de generación. No implica que el error de generación esté resuelto ni agrega datos personales al contexto.

Pruebas de clasificación y privacidad del diagnóstico, Flutter añade mensajes comprobables (ejecución Windows pendiente). Sin migraciones; revertir commit para reversión.
