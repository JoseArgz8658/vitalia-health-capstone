import 'package:flutter/material.dart';
import '../examenes/registro/panel_registro_page.dart';
import '../profesional/profesional_page.dart';
import '../administracion/administracion_page.dart';

/// Selector de prototipo, sin sesiones ni autorización real.
class SeleccionRolesPage extends StatelessWidget {
  const SeleccionRolesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(width: 480, child: Card(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.health_and_safety_outlined, size: 64,
              color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Vitalia Health', textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            const Text('Explorar interfaces por rol', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            _boton(context, 'Paciente', const PanelRegistroPage()),
            _boton(context, 'Profesional', const ProfesionalPage()),
            _boton(context, 'Administrador', const AdministracionPage()),
            const SizedBox(height: 16),
            const Text('Demostración con datos ficticios. '
              'Elegir un rol aquí no concede permisos reales.',
              textAlign: TextAlign.center),
          ]),
      ))),
    ))),
  );
  Widget _boton(BuildContext context, String texto, Widget pagina) =>
    Padding(padding: const EdgeInsets.only(bottom: 12),
      child: FilledButton.tonal(onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => pagina)), child: Text(texto)));
}
