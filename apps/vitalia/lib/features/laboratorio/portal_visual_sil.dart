import 'package:flutter/material.dart';

import '../../core/tema_vitalia.dart';

/// Cabecera con ilustración vectorial de familia y laboratorio, sin
/// fotografías de pacientes ni activos externos de licencias inciertas.
class PortalHeroSil extends StatelessWidget {
  const PortalHeroSil({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.icon = Icons.health_and_safety_outlined,
    this.action,
    this.compact = false,
    this.showLaboratoryArt = true,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;
  final bool compact;
  final bool showLaboratoryArt;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(23),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF173B53), Color(0xFF286E79), Color(0xFF2F8783)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final withArt = showLaboratoryArt &&
                constraints.maxWidth >= 815 &&
                !compact;
            final intro = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0x2DFFFFFF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: 21),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        eyebrow.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFD1F0EF),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.35,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 19),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: compact ? 26 : 33,
                    height: 1.16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 11),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFE2F1F2),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                if (action case final Widget actionWidget) ...[
                  const SizedBox(height: 21),
                  actionWidget,
                ],
              ],
            );

            return Stack(
              children: [
                const Positioned(
                  left: -60,
                  bottom: -90,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0x0BFFFFFF),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -90,
                  right: -75,
                  child: IgnorePointer(
                    child: Container(
                      width: 265,
                      height: 265,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0x35FFFFFF),
                          width: 28,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 19 : 30,
                    vertical: compact ? 25 : 33,
                  ),
                  child: withArt
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 7, child: intro),
                            const SizedBox(width: 22),
                            const Expanded(
                              flex: 4,
                              child: PortalLaboratorioIlustracionSil(),
                            ),
                          ],
                        )
                      : intro,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Composición médica/familiar puramente decorativa. No utiliza ni
/// sugiere resultados clínicos, diagnósticos o personal acreditado.
class PortalLaboratorioIlustracionSil extends StatelessWidget {
  const PortalLaboratorioIlustracionSil({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ilustración de bienestar familiar y laboratorio clínico',
      image: true,
      child: SizedBox(
        height: 218,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 6,
              left: 24,
              right: 8,
              bottom: 15,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x24FFFFFF),
                  borderRadius: BorderRadius.circular(27),
                  border: Border.all(color: const Color(0x50FFFFFF)),
                ),
              ),
            ),
            Positioned(
              top: 30,
              left: 44,
              right: 28,
              bottom: 34,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF4FBF9),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F032D3B),
                      blurRadius: 23,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.favorite,
                              color: ColoresVitalia.verde, size: 18),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'SALUD Y CERCANÍA',
                              style: TextStyle(
                                color: ColoresVitalia.azulActivo,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.family_restroom,
                        color: Color(0xFF2C7A7B),
                        size: 77,
                      ),
                      const Spacer(),
                      const Text(
                        'Un espacio para cuidarte',
                        style: TextStyle(
                          fontSize: 11,
                          color: ColoresVitalia.azulActivo,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 7,
              right: 0,
              child: _ArtBadge(
                icon: Icons.biotech_outlined,
                background: const Color(0xFFE9F4F1),
              ),
            ),
            Positioned(
              bottom: 4,
              left: 0,
              child: _ArtBadge(
                icon: Icons.monitor_heart_outlined,
                background: const Color(0xFFE6F1F8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtBadge extends StatelessWidget {
  const _ArtBadge({required this.icon, required this.background});

  final IconData icon;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1D102F38),
            blurRadius: 15,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: ColoresVitalia.azulActivo, size: 27),
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
