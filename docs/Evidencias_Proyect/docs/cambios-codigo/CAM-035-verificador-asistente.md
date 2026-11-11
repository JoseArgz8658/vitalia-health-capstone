# CAM-035 — Corrección del verificador del asistente

## Alcance y autorización
Se corrigió el fallo reportado en el asistente. El cambio se limitó al verificador y no requirió cambios en las tablas ni en las migraciones.

## Corrección
El modelo ficticio del verificador devuelve definiciones para explicación y respuesta sin definiciones para chat. Un indicador desconocido conserva su declaración de incertidumbre. Se verifica reutilización de la explicación y se compara el número de llamadas antes y después de la pregunta fuera de contexto.

## Validación
Compilación y pruebas del asistente, incluida regresión del contrato de explicación para Alfa. La comprobación con PostgreSQL debe ejecutarse en Windows; no se dispone aquí de esa base.

## Reversión
Restaurar el verificador y la prueba desde el commit anterior. No requiere revertir migraciones.
