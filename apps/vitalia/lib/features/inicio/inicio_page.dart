import 'package:flutter/material.dart';
import '../panel/panel_page.dart';

/// Selección demostrativa: no inicia sesiones reales.
class InicioPage extends StatelessWidget {
  const InicioPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(width: 460, child: Card(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.health_and_safety_outlined, size: 64,
              color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Vitalia Health', textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            const Text('Tus exámenes, organizados en un solo lugar.',
              textAlign: TextAlign.center),
            const SizedBox(height: 28),
            const Text('Explorar prototipo visual', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            for (final rol in RolDemo.values)
              Padding(padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => PanelPage(rol: rol))),
                  child: Text('Ver como ${rol.etiqueta}'),
                )),
            const Text('Demostración sin inicio de sesión ni datos reales.',
              textAlign: TextAlign.center),
          ],
        ),
      ))),
    ))),
  );
}
