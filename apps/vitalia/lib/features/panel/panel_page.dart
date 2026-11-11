import 'package:flutter/material.dart';

enum RolDemo {
  paciente('Paciente'), profesional('Profesional'), administrador('Administrador');
  const RolDemo(this.etiqueta);
  final String etiqueta;
}

/// Navegación local por rol para revisión visual antes de integrar permisos.
class PanelPage extends StatefulWidget {
  const PanelPage({super.key, required this.rol});
  final RolDemo rol;
  @override
  State<PanelPage> createState() => _PanelPageState();
}
class _PanelPageState extends State<PanelPage> {
  int _seleccion = 0;
  List<String> get _secciones => switch(widget.rol) {
    RolDemo.paciente => ['Mis exámenes', 'Historial', 'Mi perfil'],
    RolDemo.profesional => ['Pacientes', 'Exámenes', 'Revisión'],
    RolDemo.administrador => ['Usuarios', 'Permisos', 'Auditoría'],
  };
  IconData _icono(int i) => [Icons.folder_outlined, Icons.history, Icons.person_outline][i];
  @override
  Widget build(BuildContext context) {
    final secciones = _secciones;
    return Scaffold(
      appBar: AppBar(title: Text('Vitalia · ${widget.rol.etiqueta}')),
      body: LayoutBuilder(builder: (context, constraints) {
        final contenido = _contenido(secciones[_seleccion]);
        if (constraints.maxWidth < 800) return contenido;
        return Row(children: [
          NavigationRail(
            selectedIndex: _seleccion,
            onDestinationSelected: (i) => setState(() => _seleccion = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (var i = 0; i < secciones.length; i++)
                NavigationRailDestination(icon: Icon(_icono(i)), label: Text(secciones[i])),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: contenido),
        ]);
      }),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 800
        ? NavigationBar(
          selectedIndex: _seleccion,
          onDestinationSelected: (i) => setState(() => _seleccion = i),
          destinations: [
            for (var i = 0; i < secciones.length; i++)
              NavigationDestination(icon: Icon(_icono(i)), label: secciones[i]),
          ],
        ) : null,
    );
  }
  Widget _contenido(String titulo) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Align(alignment: Alignment.topCenter,
      child: SizedBox(width: 1000, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('Prototipo visual · servicios sin conectar'),
          const SizedBox(height: 24),
          Card(child: Padding(padding: const EdgeInsets.all(32), child: Column(
            children: [
              Icon(Icons.folder_open, size: 64,
                color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Aún no hay información en $titulo',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text('Aquí se mostrará información autorizada cuando se integre el backend.',
                textAlign: TextAlign.center),
            ],
          ))),
          const SizedBox(height: 24),
          const Text('La IA se integrará más adelante. No sustituirá la evaluación profesional.'),
        ],
      )),
    ),
  );
}
