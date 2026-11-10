import 'package:flutter/material.dart';

import '../../core/tema_vitalia.dart';

/// Guía de recepción basada en acciones clínicas reales, no en datos DEMO.
class OperatorStepGuide extends StatelessWidget {
  const OperatorStepGuide({
    super.key,
    required this.current,
    required this.steps,
  });

  final int current;
  final List<({String title, String detail, IconData icon})> steps;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 960 ? 4
          : constraints.maxWidth >= 520 ? 2 : 1;
      const gap = 10.0;
      final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (var i = 0; i < steps.length; i++)
          SizedBox(
            width: width,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: i == current ? ColoresVitalia.verdeSuave : Colors.white,
                border: Border.all(
                  width: i == current ? 1.5 : 1,
                  color: i == current ? ColoresVitalia.verde : ColoresVitalia.borde,
                ),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: i < current
                      ? ColoresVitalia.verde : ColoresVitalia.azulSuave,
                  child: i < current
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : Text((i + 1).toString(), style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: ColoresVitalia.azulActivo,
                        )),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(steps[i].title,
                      style: const TextStyle(fontWeight: FontWeight.w700,
                        color: ColoresVitalia.texto)),
                    Text(steps[i].detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ColoresVitalia.textoSecundario)),
                  ],
                )),
              ]),
            ),
          ),
      ]);
    },
  );
}

/// Respuesta de la interfaz a la pregunta "¿qué debo hacer ahora?".
class OperatorNextStep extends StatelessWidget {
  const OperatorNextStep({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.accent = ColoresVitalia.azul,
    this.background = ColoresVitalia.azulSuave,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color accent;
  final Color background;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: accent.withValues(alpha: .18)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: accent),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(
            fontWeight: FontWeight.w800, color: accent)),
          const SizedBox(height: 4),
          Text(message, style: const TextStyle(height: 1.35)),
          if (action != null) ...[
            const SizedBox(height: 10),
            action!,
          ],
        ],
      )),
    ]),
  );
}
