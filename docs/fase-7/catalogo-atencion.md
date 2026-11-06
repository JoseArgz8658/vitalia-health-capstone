# Catálogo de atención — fase 7

Preparé el servicio previo a la selección del profesional por examen. La pantalla de carga conserva su funcionamiento anterior hasta conectar la selección con persistencia y permisos por documento. Véase CAM-096. (José Aránguiz)

## Consulta

Utilizo `GET /api/care/catalog?communeCode=13125` con sesión Bearer de paciente. El ejemplo identifica Quilicura mediante código territorial. Admito filtros opcionales UUID de clínica, sucursal y especialidad, y `offset` entero desde cero. La respuesta contiene `communeCode`, `items` y `nextOffset`; una página entrega hasta 30 opciones. Debo continuar por `nextOffset` mientras no sea nulo. El catálogo cambia con las habilitaciones; no representa horas disponibles ni una reserva. (José Aránguiz)

Una comuna existente sin opciones devuelve lista vacía. No amplío silenciosamente a otras comunas, no asigno un profesional automáticamente y no uso el domicilio del perfil sin confirmación. Una comuna inexistente produce un error de filtro. El catálogo no determina urgencias, diagnósticos ni tratamientos. (José Aránguiz)

## Verificación local

Después de actualizar la rama `fase-7/03-atencion-examen`, ejecuto `npm test` en backend. Espero 706 pruebas en 54 suites. No hay cambios Flutter en este incremento. (José Aránguiz)

Con 020 y los permisos anteriores ya aplicados, puedo ejecutar el verificador desde backend con credenciales administrativas temporales, siguiendo el mismo procedimiento de restauración de variables usado para migraciones: (José Aránguiz)

```powershell
node --env-file=.env dist/database/verify-care-catalog.js
if ($LASTEXITCODE -ne 0) {
    throw "Falló la verificación del catálogo de atención."
}
```

Espero `Catálogo de atención: 28 comprobaciones correctas. Datos sintéticos revertidos.` El verificador crea únicamente datos ficticios dentro de una transacción y los revierte. No requiere una migración nueva ni más permisos para la aplicación. (José Aránguiz)

## Continuación

Completaré el formulario por pasos, dirección/contacto confirmados y selección persistida por documento antes de dar por terminada la carga con atención. Revalidaré en servidor las relaciones y credenciales al confirmar el envío. La consulta de este catálogo no otorga acceso al paciente ni permite atender sus exámenes. (José Aránguiz)
