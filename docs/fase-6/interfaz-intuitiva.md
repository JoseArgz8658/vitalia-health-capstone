# Fase 6 — Interfaz intuitiva

Rama: fase-6/interfaz-intuitiva. Base: 4e946fed, conservada en fase-5/informe-completo.

Objetivo: convertir los flujos actuales en una interfaz comprensible para pacientes y profesionales, compartida entre web y Android.

## Orden de implementación
- [ ] Preparar logo completo y símbolo para aplicación; revisar nitidez y márgenes.
- [x] Definir estilos compartidos con paleta acordada y acciones con texto e iconos.
- [x] Inicio e historial del paciente: acción principal clara y estados visibles.
- [x] Detalle de examen: original, extracción IA, copia revisada y observaciones diferenciados.
- [x] Profesional: pendientes y formulario de revisión, con acciones claras.
- [x] Chat propio con burbujas, preguntas sugeridas, indicador de espera y conservación de conversación.
- [ ] Probar tamaños móviles, teclado, texto ampliado y navegación web.
- [ ] Registrar capturas y pruebas para informe de avance.

La identidad visual usa azul #2867B2, verde #39A59A, fondo #EAF2FB, blanco #FFFFFF, texto #263238 y bordes #D7E0E5. El color no es el único medio para distinguir estados.

## Retroalimentación docente aportada por el usuario
Mejorar mockups e interfaz; justificar asignación administrativa provisional. Elección de médico por paciente, derivación clínica y multiclínica requieren diseño de datos y permisos posterior: no se presentan como implementados en esta fase.

## Pendientes conservados
Ver ../pendientes/ia-cobertura-rendimiento.md antes de retomar IA.
Modelo relacional actual, ampliación de datos y documentación académica siguen pendientes; diferenciar realidad implementada de propuesta.

## Estado del avance
Implementadas mejoras de acceso y registro, símbolo y fondo, historial, consulta dedicada del profesional, resultados del paciente, chat dedicado y acceso flotante a IA. El usuario informó que las vistas se ven más ordenadas. Esto no equivale a una prueba completa de accesibilidad.

Pendientes: iconos de instalación Android, comprobación sistemática de teclado/texto ampliado/tamaños, capturas para la entrega y ajustes derivados de las pruebas. El símbolo está preparado; no se declara completado el logo completo ni los iconos Android.

Bloque CAM-068: avisos compartidos, márgenes adaptativos, estados de carga/listas vacías y tarjetas de explicación. Validación Flutter pendiente en el equipo del usuario.
