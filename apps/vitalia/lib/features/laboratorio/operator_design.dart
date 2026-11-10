import 'package:flutter/material.dart';

import '../../core/tema_vitalia.dart';

/// Componentes visuales del puesto de trabajo SIL.
/// La información y las acciones siempre son entregadas por la página que
/// consulta la API; esta biblioteca no contiene pacientes ni cifras ficticias.
abstract final class OperatorPalette {
  static const navy = Color(0xFF102D45);
  static const deep = Color(0xFF0E4561);
  static const teal = Color(0xFF137B82);
  static const blue = Color(0xFF2567B1);
  static const ink = ColoresVitalia.texto;
  static const muted = ColoresVitalia.textoSecundario;
  static const stroke = ColoresVitalia.borde;
}

class OperatorHero extends StatelessWidget {
  const OperatorHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.compact = false,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [OperatorPalette.navy, OperatorPalette.deep, OperatorPalette.teal],
        ),
        boxShadow: [
          BoxShadow(
            color: OperatorPalette.navy.withValues(alpha: .10),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -48,
            top: -118,
            child: Container(
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .11),
                  width: 38,
                ),
              ),
            ),
          ),
          Positioned(
            right: 36,
            bottom: -64,
            child: Icon(
              Icons.biotech_outlined,
              size: 222,
              color: Colors.white.withValues(alpha: .075),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 21 : 27,
              vertical: compact ? 22 : 26,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: text.labelMedium?.copyWith(
                    color: const Color(0xFFC7E5F0),
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: (compact ? text.headlineSmall : text.headlineMedium)?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Text(
                    subtitle,
                    style: text.bodyMedium?.copyWith(
                      color: const Color(0xFFE1EDF4),
                      height: 1.4,
                    ),
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 19),
                  Wrap(spacing: 10, runSpacing: 10, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OperatorMetricCard extends StatelessWidget {
  const OperatorMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.accent,
    required this.tint,
    required this.onTap,
    this.caption,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color accent;
  final Color tint;
  final VoidCallback? onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: OperatorPalette.stroke),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: tint.withValues(alpha: .55),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 39,
                  height: 39,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const Spacer(),
                Icon(Icons.north_east_rounded, color: accent, size: 18),
              ]),
              const SizedBox(height: 11),
              Text(
                '$count',
                style: text.headlineMedium?.copyWith(
                  color: OperatorPalette.navy,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: OperatorPalette.ink,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 5),
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: OperatorPalette.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class OperatorActionTile extends StatelessWidget {
  const OperatorActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.count,
    this.accent = OperatorPalette.blue,
    this.background = ColoresVitalia.azulSuave,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final int? count;
  final VoidCallback? onTap;
  final Color accent;
  final Color background;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: OperatorPalette.stroke),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 21, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: OperatorPalette.ink,
              )),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: OperatorPalette.muted,
                ),
              ),
            ]),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 32),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(color: accent, fontWeight: FontWeight.w800),
              ),
            ),
          ],
          const SizedBox(width: 7),
          Icon(Icons.chevron_right, color: accent, size: 20),
        ]),
      ),
    ),
  );
}

class OperatorDistributionBar extends StatelessWidget {
  const OperatorDistributionBar({
    super.key,
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text('$count', style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: OperatorPalette.navy,
          )),
        ]),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 9,
            backgroundColor: ColoresVitalia.fondoAzul,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            semanticsLabel: '$label: $count de $total órdenes',
          ),
        ),
      ]),
    );
  }
}

class OperatorInfoNote extends StatelessWidget {
  const OperatorInfoNote({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.color = ColoresVitalia.azul,
    this.background = ColoresVitalia.azulSuave,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: color.withValues(alpha: .12)),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
        )),
        const SizedBox(height: 3),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
      ])),
    ]),
  );
}
