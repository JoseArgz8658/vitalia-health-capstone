import 'package:flutter/material.dart';

import '../../core/tema_vitalia.dart';

/// Piezas visuales compartidas por el portal y el resumen de informes SIL.
//// Mantienen el tono clínico y no muestran información clínica inventada.
class PortalHeroSil extends StatelessWidget {
  const PortalHeroSil({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.icon = Icons.health_and_safety_outlined,
    this.action,
    this.compact = false,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF193E55), Color(0xFF286C7A), Color(0xFF348A89)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -45,
              child: IgnorePointer(
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0x44FFFFFF),
                      width: 27,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -110,
              right: 145,
              child: IgnorePointer(
                child: Container(
                  width: 215,
                  height: 215,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x0DFFFFFF),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 19 : 28,
                vertical: compact ? 23 : 30,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: const Color(0x2FFFFFFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: Colors.white, size: 21),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          eyebrow.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.25,
                            color: Color(0xFFE1F3F4),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: compact ? 24 : 30,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 9),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 610),
                    child: Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFE9F5F5),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (action case final Widget actionWidget) ...[
                    const SizedBox(height: 20),
                    actionWidget,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PortalIndicadorSil extends StatelessWidget {
  const PortalIndicadorSil({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.accent = ColoresVitalia.azul,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: ColoresVitalia.borde),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: ColoresVitalia.fondoAzul,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(Icons.arrow_outward,
                        size: 18, color: accent),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ColoresVitalia.texto,
                  fontWeight: FontWeight.w800,
                  fontSize: 23,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: ColoresVitalia.texto,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                detail,
                style: const TextStyle(
                  color: ColoresVitalia.textoSecundario,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PortalEncabezadoSeccionSil extends StatelessWidget {
  const PortalEncabezadoSeccionSil({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      spacing: 14,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ColoresVitalia.texto,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: ColoresVitalia.textoSecundario,
              ),
            ),
          ],
        ),
        if (action != null) action!,
      ],
    );
  }
}
