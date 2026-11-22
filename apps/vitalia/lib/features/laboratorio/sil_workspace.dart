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

/// Navegación superior compartida por las estaciones SIL.
///
/// En pantallas estrechas muestra controles de desplazamiento y mantiene
/// visible la pestaña seleccionada, incluso si se cambia desde un acceso
/// rápido fuera de la barra.
class SilWorkspaceTopNavigation extends StatefulWidget {
  const SilWorkspaceTopNavigation({
    super.key,
    required this.tabs,
    this.label = 'Secciones',
  });

  final List<SilWorkspaceTab> tabs;
  final String label;

  @override
  State<SilWorkspaceTopNavigation> createState() =>
      _SilWorkspaceTopNavigationState();
}

class _SilWorkspaceTopNavigationState
    extends State<SilWorkspaceTopNavigation> {
  final ScrollController _controller = ScrollController();
  final List<GlobalKey> _tabKeys = [];
  bool _overflow = false;
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _syncKeys();
    _controller.addListener(_updateScrollButtons);
    _scheduleRevealSelected();
  }

  @override
  void didUpdateWidget(covariant SilWorkspaceTopNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    final previous = oldWidget.tabs.indexWhere((tab) => tab.selected);
    final current = widget.tabs.indexWhere((tab) => tab.selected);
    if (previous != current || oldWidget.tabs.length != widget.tabs.length) {
      _scheduleRevealSelected();
    }
  }

  void _syncKeys() {
    while (_tabKeys.length < widget.tabs.length) {
      _tabKeys.add(GlobalKey());
    }
    if (_tabKeys.length > widget.tabs.length) {
      _tabKeys.removeRange(widget.tabs.length, _tabKeys.length);
    }
  }

  void _scheduleRevealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _revealSelected();
    });
  }

  void _revealSelected() {
    final index = widget.tabs.indexWhere((tab) => tab.selected);
    if (index < 0 || index >= _tabKeys.length) return;
    final target = _tabKeys[index].currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
      // En un cambio de pestaña debe servir en ambas direcciones del scroll.
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  void _updateScrollButtons() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final back = _overflow && position.pixels > 1;
    final forward = _overflow &&
        position.pixels < position.maxScrollExtent - 1;
    if (back != _canScrollBack || forward != _canScrollForward) {
      setState(() {
        _canScrollBack = back;
        _canScrollForward = forward;
      });
    }
  }

  void _refreshOverflow(double availableWidth) {
    if (!mounted || !_controller.hasClients) return;
    // El ancho total de las pestañas no depende de la presencia de flechas.
    // Esto evita que estas permanezcan visibles después de agrandar la ventana.
    final contentWidth = 24.0 + _tabKeys.fold<double>(
      0, (width, key) => width + (key.currentContext?.size?.width ?? 0),
    );
    final overflow = contentWidth > availableWidth + 1;
    if (_overflow != overflow) {
      setState(() => _overflow = overflow);
      _scheduleRevealSelected();
    }
    _updateScrollButtons();
  }

  void _scrollBy(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final step = position.viewportDimension * 0.75;
    final target = (position.pixels + direction * step)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_updateScrollButtons);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      color: ColoresVitalia.blanco,
      border: Border(bottom: BorderSide(color: ColoresVitalia.borde)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _refreshOverflow(constraints.maxWidth);
        });
        return Semantics(
          label: widget.label,
          child: Row(
            children: [
              if (_overflow)
                IconButton(
                  tooltip: 'Mostrar secciones anteriores',
                  onPressed: _canScrollBack ? () => _scrollBy(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7,
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < widget.tabs.length; i++)
                        Padding(
                          key: _tabKeys[i],
                          padding: const EdgeInsets.only(right: 6),
                          child: Semantics(
                            selected: widget.tabs[i].selected,
                            child: TextButton.icon(
                              onPressed: widget.tabs[i].onPressed,
                              icon: Icon(widget.tabs[i].icon, size: 18),
                              label: Text(widget.tabs[i].label, maxLines: 1),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 44),
                                foregroundColor: widget.tabs[i].selected
                                    ? ColoresVitalia.azulActivo
                                    : ColoresVitalia.textoSecundario,
                                backgroundColor: widget.tabs[i].selected
                                    ? ColoresVitalia.azulSuave
                                    : Colors.transparent,
                                textStyle: TextStyle(
                                  fontWeight: widget.tabs[i].selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                ),
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
              if (_overflow)
                IconButton(
                  tooltip: 'Mostrar más secciones',
                  onPressed: _canScrollForward ? () => _scrollBy(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
            ],
          ),
        );
      },
    ),
  );
}

 
/// Indica el contexto de acceso sin exponer identificadores internos.
class SilWorkspaceRoleLabel extends StatelessWidget {
  const SilWorkspaceRoleLabel({
    super.key,
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Rol actual: $label',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: ColoresVitalia.azulSuave,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ColoresVitalia.borde),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 17, color: ColoresVitalia.azulActivo),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(
          color: ColoresVitalia.azulActivo,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        )),
      ]),
    ),
  );
}

/// Métrica contextual, sin acción implícita ni datos de ejemplo.
class SilWorkspaceSummaryStat extends StatelessWidget {
  const SilWorkspaceSummaryStat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: ColoresVitalia.blanco,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: ColoresVitalia.borde),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: ColoresVitalia.verdeSuave,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: ColoresVitalia.verde, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: ColoresVitalia.azulActivo,
          )),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: ColoresVitalia.textoSecundario,
          )),
        ],
      )),
    ]),
  );
}

/// Explica las etapas del SIL, sin presentar un progreso ficticio.
class SilWorkspaceProcessPath extends StatelessWidget {
  const SilWorkspaceProcessPath({super.key});

  static const _steps = [
    'Recepción',
    'Verificación',
    'Orden',
    'Revisión',
    'Publicación',
  ];

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Etapas del proceso', style:
            Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(height: 5),
          const Text(
            'Guía del recorrido postanalítico. No representa el estado de una orden.',
            style: TextStyle(
              fontSize: 12,
              color: ColoresVitalia.textoSecundario,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _steps.length; i++)
              Semantics(
                label: 'Etapa ${i + 1} de ${_steps.length}: ${_steps[i]}',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11, vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: ColoresVitalia.fondoAzul,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ColoresVitalia.borde),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${i + 1}', style: const TextStyle(
                      color: ColoresVitalia.azulActivo,
                      fontWeight: FontWeight.w800,
                    )),
                    const SizedBox(width: 8),
                    Text(_steps[i], style: const TextStyle(
                      color: ColoresVitalia.texto,
                      fontWeight: FontWeight.w600,
                    )),
                  ]),
                ),
              ),
          ]),
        ],
      ),
    ),
  );
}
