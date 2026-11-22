# Vitalia Health — Comprobaciones de seguridad F18 y F21

**Corte documental:** noviembre de 2026. **Estado:** protocolo de auditoría
pendiente de aplicar en el computador anfitrión y desde un equipo externo.
Se trabaja exclusivamente con la instancia académica y datos sintéticos.

Este procedimiento no acredita un despliegue apto para uso clínico real. Su
objetivo es reemplazar suposiciones por verificaciones reproducibles y
evidencias acotadas, sin revelar secretos ni afectar el funcionamiento.

## 1. Hallazgo F18: usuario de la base de datos

El `compose.yaml` vigente asigna `POSTGRES_USER` desde `PGUSER`; la API
usa el mismo `PGUSER`. En una **instalación inicial** de la imagen oficial
de PostgreSQL, `POSTGRES_USER` crea el usuario administrador de la base
(superusuario). En un volumen ya existente el estado puede ser diferente,
y las variables de inicialización no cambian privilegios retroactivamente.

Evidencia histórica: `docs/evidencias/E07_privilegios.txt` contiene un
rol `vitalia` con privilegios altos. No demuestra su estado actual.

**Fuentes de referencia:**
- Imagen oficial PostgreSQL: https://hub.docker.com/_/postgres
- Guía del equipo: [evidencia F17–F21](../evidencias/seguridad/README.md)

### Ejecutar en solo lectura (administrador autorizado)

Desde la raíz del repositorio en el PC anfitrión:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\auditar-postgres-sil.ps1
```

El script:
- Comprueba que el servicio `api` y `postgres` estén ejecutándose.
- Comprueba, **sin imprimir nombres**, que los servicios usan el mismo
  usuario/base y que la base sea `vitalia`.
- Ejecuta `deploy/sql/auditar-privilegios-sil.sql` dentro de una transacción
  PostgreSQL `READ ONLY`.
- Imprime solo indicadores booleanos de privilegios administrativos.
  No consulta tablas de pacientes, órdenes, documentos ni credenciales.
- No crea usuarios, no cambia roles, no edita `.env` y no reinicia servicios.

Si aparece `rol_conexion=PRIVILEGIOS_ADMINISTRATIVOS_DETECTADOS`,
clasificar F18 como **riesgo confirmado por consulta técnica** para esa
instancia y fecha. Si no aparecen esos atributos, aún falta revisar permisos
efectivos de esquema/tablas, herencia de roles y privilegios concedidos;
**no** declarar principio de mínimo privilegio acreditado por un único
resultado.

Si el script falla, dejarlo como **pendiente de auditoría** y revisar el
motivo; nunca reconfigurar PostgreSQL o cambiar claves solo para completar
la evidencia.

### Remediación futura (requiere autorización independiente)

Diseñar la separación entre rol de migración/administración y rol de
aplicación con privilegios mínimos sobre objetos permitidos. Antes de
aplicarla, inventariar dependencias, respaldar y ensayar en una copia
aislada, documentar cómo volver a la configuración previa y probar
todos los flujos. **No** retirar permisos al usuario en servicio
ni alterar la inicialización de PostgreSQL automáticamente.

## 2. Hallazgo F21: exposición externa y Tailscale

Desde el computador anfitrión, solo consultar estados:

```powershell
tailscale serve status
tailscale funnel status
```

- `Serve` proporciona acceso privado a equipos autorizados de la red.
- `Funnel` hace público un servicio configurado con él. Si hay un Funnel
  habilitado, identificar el puerto y destino en un registro **privado** y
  acordar su retiro o aislamiento; no cambiarlo en esta auditoría.
- Evitar publicar salidas completas: pueden incluir nombres de equipo,
  nombres de tailnet, direcciones IP o rutas internas.
- Revisar en la administración de Tailscale los grants/ACL efectivos para
  la identidad externa de prueba: solo acceso a HTTPS **443**, sin permitir
  445 (SMB), 3389 (RDP) o 5432 (PostgreSQL).

La comprobación desde otro equipo autorizado, conectado a Tailscale,
puede documentar conectividad de puertos sin autenticarse ni acceder
a datos. Sustituir `HOST_PRIVADO` por el nombre/IPv4 de Tailscale
obtenido desde un canal autorizado, nunca por un nombre supuesto:

```powershell
Test-NetConnection -ComputerName HOST_PRIVADO -Port 443
Test-NetConnection -ComputerName HOST_PRIVADO -Port 445
Test-NetConnection -ComputerName HOST_PRIVADO -Port 3389
Test-NetConnection -ComputerName HOST_PRIVADO -Port 5432
```

Esperamos que 443 responda y los demás no. **Importante:** un puerto
que no responde tampoco demuestra por sí solo que la política Tailscale
lo bloquee; el servicio podría estar apagado. La evidencia de cierre
incluye por separado la política/grants aplicados al usuario de prueba
y una comprobación de conectividad desde ese usuario. No ejecutar
escaneos generales de red, no abrir servicios solo para comprobar un
bloqueo y no cambiar reglas durante el ensayo.

Fuentes oficiales:
- https://tailscale.com/docs/reference/tailscale-cli/serve
- https://tailscale.com/docs/reference/tailscale-cli/funnel
- https://tailscale.com/docs/features/access-control

## 3. Registro recomendado (solo metadatos)

| Campo | Qué registrar |
| --- | --- |
| Fecha y hora (Chile) | Momento del ensayo |
| Commit y rama | Referencia exacta del código auditado |
| F18: resultado | `PRIVILEGIOS_ADMINISTRATIVOS_DETECTADOS`, `SIN_ATRIBUTOS_ADMINISTRATIVOS` o `NO_VERIFICADO` |
| F21: Serve/Funnel | Presencia/ausencia y alcance, sin publicar nombres internos |
| F21: grants/ACL | Reglas relevantes revisadas con la identidad externa de prueba |
| F21: puertos | Resultado de 443, 445, 3389 y 5432 desde ese usuario |
| Responsable | Rol de quien ejecutó y revisó; no sus credenciales |
| Limitaciones | Qué no pudo verificarse y por qué |

Conservar el acta en un entorno privado del equipo. Para evidencia pública,
publicar solo resultados resumidos y redactados, sin IP, claves, tokens,
nombres completos de dispositivos, listas de usuarios ni datos clínicos.

## 4. Criterio de cierre

- **F18:** se ha auditado el usuario efectivo; si requiere remediación,
  crear un cambio independiente con plan de migración y pruebas.
- **F21:** se ha comprobado Serve/Funnel, política de acceso y
  conectividad remota real.
- No confundir esta verificación operativa con pentesting,
  cumplimiento normativo o validación clínica.
