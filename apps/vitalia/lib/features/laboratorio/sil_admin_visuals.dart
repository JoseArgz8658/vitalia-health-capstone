import 'package:flutter/material.dart';

import '../../core/tema_vitalia.dart';

/// Datos derivados de consultas ya existentes. La UI no debe inventar totales.
class SilAdminMetric {
  const SilAdminMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? detail;
}

/// Tarjetas compactas, adaptables y legibles para vistas administrativas.
class SilAdminMetrics extends StatelessWidget {
  const SilAdminMetrics({super.key, required this.metrics});

  final List<SilAdminMetric> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final columns = constraints.maxWidth >= 900
              ? 3
              : constraints.maxWidth >= 520
                  ? 2
                  : 1;
          final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final item in metrics)
                SizedBox(
                  width: width,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: ColoresVitalia.bordeTenue),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x090E3850),
                          blurRadius: 12,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: ColoresVitalia.azulSuave,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(11),
                              child: Icon(item.icon,
                                  size: 22, color: ColoresVitalia.azul),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: ColoresVitalia.textoSecundario),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  item.value,
                                  style: Theme.of(context).textTheme.headlineSmall
                                      ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: ColoresVitalia.texto,
                                  ),
                                ),
                                if (item.detail case final String description) ...[
                                  const SizedBox(height: 4),
                                  Text(description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall
                                          ?.copyWith(color: ColoresVitalia.textoSecundario)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

/// Accesos contextuales. Mantienen las acciones al lado del laboratorio activo.
class SilAdminQuickAction extends StatelessWidget {
  const SilAdminQuickAction({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: ColoresVitalia.bordeTenue),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: ColoresVitalia.azul),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ColoresVitalia.texto)),
                      const SizedBox(height: 3),
                      Text(description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ColoresVitalia.textoSecundario,
                          )),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios,
                    size: 15, color: ColoresVitalia.textoSecundario),
              ],
            ),
          ),
        ),
      );
}
