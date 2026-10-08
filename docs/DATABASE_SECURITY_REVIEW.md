# Vitalia Health - Revisión técnica de base de datos y seguridad

## 1. Objetivo

Documentar el estado actual de la base de datos PostgreSQL de Vitalia Health, verificar su estructura y registrar oportunidades de mejora relacionadas con el almacenamiento, la integridad de los datos y la seguridad.

Esta revisión forma parte del trabajo de Datos, Almacenamiento y Seguridad del proyecto de especialidad.

## 2. Alcance

La revisión considera:

- Funcionamiento del servicio PostgreSQL en Docker.
- Existencia de las tablas del esquema public.
- Registro de migraciones aplicadas.
- Relaciones entre tablas mediante claves foráneas.
- Resultados de las pruebas automatizadas del backend.
- Privilegios de la cuenta utilizada para conectarse a PostgreSQL.
- Recomendaciones de mejora para la seguridad de la base de datos.

Las verificaciones se realizaron en un entorno local de desarrollo. No constituyen una auditoría completa de seguridad ni una certificación para producción.

## 3. Entorno revisado

- Proyecto: Vitalia Health.
- Motor de base de datos: PostgreSQL 16.15.
- Ejecución: contenedor Docker.
- Base de datos: vitalia.
- Esquema consultado: public.
- Fecha de revisión: 8 de octubre de 2026.

## 4. Resultados de la revisión técnica

### 4.1. Funcionamiento de PostgreSQL

Se verificó que el contenedor vitalia-postgres-1 ejecuta PostgreSQL 16.15 y presenta el estado healthy.

Esto confirma que el servicio se encuentra funcionando y supera la comprobación de salud configurada en Docker.

Evidencia: evidencias/E01_postgresql.txt

### 4.2. Estructura de la base de datos

Se identificaron 17 tablas en el esquema public de la base de datos vitalia.

Entre ellas se encuentran tablas destinadas a cuentas de usuario, roles, sesiones, documentos, asignaciones de profesionales, procesamiento de documentos, revisiones y registros de auditoría.

La verificación confirma la existencia de las tablas, pero no evalúa la calidad ni la cantidad de los registros almacenados.

Evidencia: evidencias/E02_tablas.txt

### 4.3. Migraciones

Se verificó el registro de 11 migraciones aplicadas, desde 001_accounts hasta 011_exam_assistant.

Estas migraciones permiten identificar la evolución registrada de la estructura de la base de datos.

Evidencia: evidencias/E03_migraciones.txt

### 4.4. Integridad referencial

PostgreSQL registra 35 restricciones de clave foránea en el esquema public.

Estas restricciones establecen relaciones entre las tablas y contribuyen a mantener la integridad referencial de los datos.

La consulta realizada confirma la existencia de las restricciones, pero no reemplaza las pruebas funcionales de inserción, actualización y eliminación de registros.

Evidencia: evidencias/E04_relaciones.txt

### 4.5. Pruebas automatizadas

Se ejecutaron las pruebas del backend mediante una imagen Docker de pruebas.

Resultados obtenidos:

- Compilación TypeScript sin errores reportados.
- 37 conjuntos de pruebas aprobados de un total de 37.
- 373 pruebas individuales aprobadas de un total de 373.
- Ninguna prueba fallida.

Estos resultados respaldan el funcionamiento de los escenarios cubiertos por las pruebas existentes. No garantizan por sí solos la ausencia de vulnerabilidades.

Evidencia: evidencias/E05_pruebas.txt

## 5. Hallazgo de seguridad: privilegios de PostgreSQL

### 5.1. Situación identificada

Se verificó que el rol vitalia posee los siguientes atributos en PostgreSQL:

- rolsuper: true.
- rolcreatedb: true.
- rolcreaterole: true.
- rolreplication: true.
- rolcanlogin: true.

Esto significa que la cuenta dispone de privilegios administrativos elevados, incluyendo acceso como superusuario.

La configuración actual utiliza esta cuenta para las conexiones de la aplicación a PostgreSQL.

Evidencia: evidencias/E07_privilegios.txt

### 5.2. Riesgo identificado

El uso de una cuenta con privilegios de superusuario para las operaciones habituales de una aplicación aumenta el impacto potencial de una vulnerabilidad o del uso indebido de sus credenciales.

En un sistema que administra información relacionada con pacientes y documentos clínicos, este riesgo merece especial atención.

La revisión confirma los privilegios del rol, pero no demuestra que exista una vulnerabilidad explotable ni que se haya producido un acceso no autorizado.

### 5.3. Nivel de riesgo propuesto

Se propone clasificar este hallazgo como riesgo alto debido al alcance de los privilegios disponibles y a la naturaleza de la información que administra el proyecto.

Esta clasificación es preliminar y deberá revisarse con el equipo considerando el entorno de despliegue, los controles existentes y la exposición real de la aplicación.

### 5.4. Recomendación: principio de mínimo privilegio

Se recomienda separar las responsabilidades mediante cuentas diferentes:

- Cuenta administrativa: destinada a tareas autorizadas de mantenimiento, administración y ejecución de migraciones.
- Cuenta de aplicación vitalia_app: destinada a las operaciones habituales del backend, con permisos limitados a los objetos y acciones estrictamente necesarios.

Antes de implementar esta separación se deberá revisar el funcionamiento del backend, el procesador de documentos, los scripts de migración, las herramientas de administración y las pruebas automatizadas.

La implementación debe coordinarse con el responsable del backend y probarse en un entorno de desarrollo antes de considerar su aplicación en otros ambientes.

### 5.5. Estado de la recomendación

Estado: propuesta pendiente de evaluación e implementación.

No se han creado nuevos roles ni modificado los privilegios existentes como parte de esta revisión documental.

## 6. Registro de evidencias

Las siguientes evidencias se encuentran almacenadas en el directorio docs/evidencias:

| Código | Archivo | Verificación |
|---|---|---|
| E01 | E01_postgresql.txt | Estado del servicio PostgreSQL en Docker. |
| E02 | E02_tablas.txt | Existencia de 17 tablas en el esquema public. |
| E03 | E03_migraciones.txt | Registro de 11 migraciones aplicadas. |
| E04 | E04_relaciones.txt | Existencia de 35 claves foráneas. |
| E05 | E05_pruebas.txt | Resultado de 373 pruebas aprobadas en 37 conjuntos. |
| E06 | Pull Request #1 | Corrección del Dockerfile de pruebas, integrada en develop. |
| E07 | E07_privilegios.txt | Privilegios administrativos del rol vitalia. |

Referencia E06:
https://github.com/JoseArgz8658/vitalia-health-capstone/pull/1

## 7. Próximos pasos recomendados

1. Revisar con el equipo los permisos que necesitan el backend y el procesador de documentos.
2. Diseñar una cuenta de aplicación con privilegios mínimos.
3. Mantener separadas las tareas administrativas y las operaciones habituales de la aplicación.
4. Probar los cambios propuestos en un entorno de desarrollo antes de implementarlos.
5. Complementar la revisión con pruebas de acceso, respaldo y recuperación de datos.
6. Mantener actualizadas las evidencias técnicas cuando cambie la estructura de la base de datos.

## 8. Conclusiones

La revisión permitió verificar que PostgreSQL funciona correctamente en el entorno local y que la base de datos Vitalia Health cuenta con 17 tablas, 11 migraciones registradas y 35 claves foráneas.

Además, el backend aprobó 373 pruebas automatizadas distribuidas en 37 conjuntos.

Se identificó como oportunidad prioritaria de mejora la separación de los privilegios administrativos y los permisos utilizados por la aplicación.

Este documento entrega evidencia técnica del estado revisado y una propuesta de mejora de seguridad que deberá evaluarse con el equipo antes de su implementación.
