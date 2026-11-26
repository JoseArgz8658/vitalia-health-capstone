import 'package:flutter/material.dart';

import '../../core/tema_vitalia.dart';

/// Una fila reúne la información y la acción de un registro en la misma línea
/// cuando hay espacio. En pantallas estrechas mantiene el orden de lectura.
class SilWorkbenchRow extends StatelessWidget {
  const SilWorkbenchRow({
    super.key,
    required this.icon,
    required this.primary,
    this.secondary,
    this.action,
    this.onOpen,
    this.selected = false,
  });

  final IconData icon;
  final Widget primary;
  final Widget? secondary;
  final Widget? action;
  final VoidCallback? onOpen;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      primary,
      if (secondary != null) secondary!,
      if (action != null) action!,
    ];
    return Material(
      color: selected ? ColoresVitalia.verdeSuave : ColoresVitalia.blanco,
      child: InkWell(
        onTap: onOpen,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: ColoresVitalia.bordeTenue)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: ColoresVitalia.azulSuave,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(icon, size: 19, color: ColoresVitalia.azul),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LayoutBuilder(builder: (context, constraints) {
                    final wider = constraints.maxWidth >= 520 &&
                        MediaQuery.textScalerOf(context).scale(14) <= 18;
                    if (!wider) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in fields)
                            Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: item),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 5, child: primary),
                        if (secondary != null) ...[
                          const SizedBox(width: 14),
                          Expanded(flex: 4, child: secondary!),
                        ],
                        if (action != null) ...[
                          const SizedBox(width: 12),
                          Flexible(flex: 4, child: action!),
                        ],
                      ],
                    );
                  }),
                ),
                if (onOpen != null) const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profundidad estática para la cabecera operativa. La información queda
/// fuera de la ilustración y conserva su contraste al ampliar el texto.
class SilOperatorDeskBanner extends StatelessWidget {
  const SilOperatorDeskBanner({super.key, required this.action});

  final Widget action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF102C28), Color(0xFF235745)]),
        borderRadius: BorderRadius.all(Radius.circular(22)),
        boxShadow: [
          BoxShadow(color: Color(0x26102C28), blurRadius: 20, offset: Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Panel del laboratorio',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Recibe solicitudes, consulta órdenes y revisa informes.',
                  style: TextStyle(color: Color(0xFFDAEEE4)),
                ),
                const SizedBox(height: 16),
                action,
              ],
            ),
          ),
          if (constraints.maxWidth >= 720)
            const ExcludeSemantics(child: _DocumentStack()),
        ],
      ),
    ),
  );
}

class _DocumentStack extends StatelessWidget {
  const _DocumentStack();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    height: 112,
    child: Stack(
      alignment: Alignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          Transform.translate(
            offset: Offset((i * 12 - 12).toDouble(), (12 - i * 12).toDouble()),
            child: Transform.rotate(
              angle: -.20,
              child: Container(
                width: 84,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: const [Color(0xFF306A55), Color(0xFF5E967E), Color(0xFFC8E6D5)][i],
                  boxShadow: const [
                    BoxShadow(color: Color(0x400B201A), blurRadius: 8, offset: Offset(1, 5)),
                  ],
                ),
                child: i == 2
                    ? const Icon(Icons.assignment_outlined, size: 35, color: Color(0xFF193E33))
                    : null,
              ),
            ),
          ),
      ],
    ),
  );
}
