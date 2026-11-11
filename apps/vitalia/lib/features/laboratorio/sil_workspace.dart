import 'package:flutter/material.dart';

import '../../core/tema_vitalia.dart';

/// Firma común de las pantallas SIL.
class SilWorkspaceBrand extends StatelessWidget {
  const SilWorkspaceBrand({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/branding/vitalia-simbolo.png',
        width: 32,
        height: 32,
        excludeFromSemantics: true,
      ),
      const SizedBox(width: 10),
      const Flexible(
        child: Text(
          'Vitalia Health',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: ColoresVitalia.texto,
          ),
        ),
      ),
    ],
  );
}

/// Mantiene la secuencia de lectura en móvil y aprovecha el ancho disponible
/// cuando ambas áreas pueden mostrar sus formularios con comodidad.
class SilWorkspaceColumns extends StatelessWidget {
  const SilWorkspaceColumns({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 1,
    this.secondaryFlex = 1,
  });

  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 780
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, const SizedBox(height: 12), secondary],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: primaryFlex, child: primary),
              const SizedBox(width: 16),
              Expanded(flex: secondaryFlex, child: secondary),
            ],
          ),
  );
}

 
/// Destino real de una navegación superior, con estado seleccionado y acción.
class SilWorkspaceTab {
  const SilWorkspaceTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;
}

/// Misma navegación para las tres estaciones. La tira se desplaza
/// horizontalmente cuando la pantalla es estrecha, sin perder destinos.
class SilWorkspaceTopNavigation extends StatelessWidget {
  const SilWorkspaceTopNavigation({super.key, required this.tabs, this.label = 'Secciones'});

  final List<SilWorkspaceTab> tabs;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      color: ColoresVitalia.blanco,
      border: Border(bottom: BorderSide(color: ColoresVitalia.borde)),
    ),
    child: Semantics(
      label: label,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            for (final tab in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Semantics(
                  selected: tab.selected,
                  child: TextButton.icon(
                    onPressed: tab.onPressed,
                    icon: Icon(tab.icon, size: 18),
                    label: Text(tab.label, maxLines: 1),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 44),
                      foregroundColor: tab.selected
                          ? ColoresVitalia.azulActivo : ColoresVitalia.textoSecundario,
                      backgroundColor: tab.selected
                          ? ColoresVitalia.azulSuave : Colors.transparent,
                      textStyle: TextStyle(fontWeight: tab.selected
                          ? FontWeight.w700 : FontWeight.w500),
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
