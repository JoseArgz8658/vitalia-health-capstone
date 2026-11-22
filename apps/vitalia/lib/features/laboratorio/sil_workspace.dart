import 'package:flutter/material.dart';

import '../../core/tema_vitalia.dart';

/// Encabezado de una vista de trabajo con una zona de acciones adaptable.
class SilWorkspaceHeading extends StatelessWidget {
  const SilWorkspaceHeading({
    super.key,
    required this.title,
    this.description,
    this.actions = const [],
    this.section = false,
  });

  final String title;
  final String? description;
  final List<Widget> actions;
  final bool section;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: (section ? text.titleLarge : text.headlineMedium)?.copyWith(
              color: ColoresVitalia.texto,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (description case final String detail) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            style: text.bodyMedium?.copyWith(
              color: ColoresVitalia.textoSecundario,
            ),
          ),
        ],
      ],
    );
    if (actions.isEmpty) return heading;
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 12), buttons],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 5, child: heading),
            const SizedBox(width: 20),
            Flexible(
              flex: 6,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: buttons,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Superficie de lectura para listas y vistas con divisiones internas.
class SilWorkspaceSurface extends StatelessWidget {
  const SilWorkspaceSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: ColoresVitalia.blanco,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      side: BorderSide(color: ColoresVitalia.borde),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

/// Abre una tarea secundaria en su contexto y evita cargar el formulario
/// en la vista de trabajo hasta que se necesita.
class SilWorkspaceDisclosure extends StatelessWidget {
  const SilWorkspaceDisclosure({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => SilWorkspaceSurface(
    child: ExpansionTile(
      leading: Icon(icon, color: ColoresVitalia.azul),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      tilePadding: const EdgeInsets.symmetric(horizontal: 24),
      minTileHeight: 64,
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      shape: const Border(),
      collapsedShape: const Border(),
      children: [child],
    ),
  );
}
class SilWorkspaceStatus extends StatelessWidget {
  const SilWorkspaceStatus({
    super.key,
    required this.label,
    this.positive = false,
  });

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: positive ? ColoresVitalia.verdeSuave : ColoresVitalia.fondoAzul,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: positive
              ? ColoresVitalia.verde
              : ColoresVitalia.textoSecundario,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
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
            children: [primary, const SizedBox(height: 20), secondary],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: primaryFlex, child: primary),
              const SizedBox(width: 24),
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

/// Mantiene las secciones de trabajo a la vista en el escritorio.
class SilWorkspaceSidebar extends StatelessWidget {
  const SilWorkspaceSidebar(
      {super.key, required this.label, required this.tabs});

  final String label;
  final List<SilWorkspaceTab> tabs;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: SizedBox(
          width: 244,
          child: ColoredBox(
            color: const Color(0xFF102C3F),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                for (final tab in tabs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      selected: tab.selected,
                      child: TextButton(
                        onPressed: tab.onPressed,
                        style: TextButton.styleFrom(
                          alignment: AlignmentDirectional.centerStart,
                          foregroundColor: tab.selected
                              ? const Color(0xFF102C3F)
                              : const Color(0xFFE2EEF3),
                          disabledForegroundColor: const Color(0xFFB0C5D1),
                          backgroundColor: tab.selected
                              ? const Color(0xFFBEEFE3)
                              : Colors.transparent,
                          minimumSize: const Size.fromHeight(52),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(tab.icon, size: 20),
                            const SizedBox(width: 12),
                            Expanded(child: Text(tab.label)),
                          ],
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

class SilWorkspaceBottomNavigation extends StatelessWidget {
  const SilWorkspaceBottomNavigation({
    super.key,
    required this.label,
    required this.tabs,
  });

  final String label;
  final List<SilWorkspaceTab> tabs;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: ColoresVitalia.borde)),
    ),
    child: SafeArea(
      top: false,
      child: Semantics(
        label: label,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              for (final tab in tabs)
                Expanded(
                  child: Semantics(
                    selected: tab.selected,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        foregroundColor: tab.selected
                            ? ColoresVitalia.azulActivo
                            : ColoresVitalia.textoSecundario,
                        backgroundColor: tab.selected
                            ? ColoresVitalia.azulSuave : Colors.transparent,
                      ),
                      onPressed: tab.onPressed,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(tab.icon, size: 20),
                          const SizedBox(height: 3),
                          Text(tab.label, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SilWorkspaceBanner extends StatelessWidget {
  const SilWorkspaceBanner({
    super.key,
    required this.title,
    required this.detail,
    required this.action,
  });

  final String title;
  final String detail;
  final Widget action;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF12384B),
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Text(detail,
                  style:
                      const TextStyle(color: Color(0xFFD9E9EF), height: 1.45)),
              const SizedBox(height: 20),
              action,
            ],
          ),
        ),
      );
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
                                minimumSize: const Size(48, 48),
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
