import 'package:flutter/material.dart';

/// Vistas de administración de solo lectura sobre ejemplos ficticios.
class AdministracionPage extends StatefulWidget {
  const AdministracionPage({super.key});
  @override
  State<AdministracionPage> createState() => _AdministracionPageState();
}
class _AdministracionPageState extends State<AdministracionPage> {
  int _seccion = 0;
  String _busqueda = '';
  static const _titulos = ['Usuarios', 'Permisos', 'Auditoría'];
  static const _usuarios = [
    ('Paciente demo 001', 'Paciente'),
    ('Profesional demo 001', 'Profesional'),
    ('Administrador demo 001', 'Administrador'),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Administración')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: Center(child: SizedBox(width: 1000, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_titulos[_seccion], style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('Solo lectura · ejemplos ficticios · sin cambios de permisos reales'),
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 8, children: [
            for (var i = 0; i < _titulos.length; i++)
              ChoiceChip(label: Text(_titulos[i]), selected: _seccion == i,
                onSelected: (_) => setState(() => _seccion = i)),
          ]),
          const SizedBox(height: 24),
          if (_seccion == 0) ...[
            TextField(decoration: const InputDecoration(labelText: 'Buscar usuario demo',
              prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: (valor) => setState(() => _busqueda = valor.trim())),
            const SizedBox(height: 12),
            if (!_usuarios.any((u) => u.$1.toLowerCase().contains(_busqueda.toLowerCase())))
              const Text('Sin coincidencias.'),
            for (final usuario in _usuarios.where((u) =>
              u.$1.toLowerCase().contains(_busqueda.toLowerCase())))
              Card(child: ListTile(leading: const Icon(Icons.person_outline),
                title: Text(usuario.$1), subtitle: Text(usuario.$2))),
          ],
          if (_seccion == 1) ...[
            const Card(child: ListTile(title: Text('Paciente'),
              subtitle: Text('Consulta de sus propios exámenes e historial.'))),
            const Card(child: ListTile(title: Text('Profesional'),
              subtitle: Text('Consulta y revisión de pacientes expresamente autorizados.'))),
            const Card(child: ListTile(title: Text('Administrador'),
              subtitle: Text('Gestión de usuarios, roles, permisos y auditoría.'))),
            const Text('Resumen del alcance documentado. La matriz detallada de acciones '
              'se validará antes de implementar autorización.'),
          ],
          if (_seccion == 2) ...[
            const Card(child: ListTile(leading: Icon(Icons.fact_check_outlined),
              title: Text('Evento de ejemplo: consulta de examen'),
              subtitle: Text('Profesional demo 001 · Examen demo 001 · 30/09/2026 10:00'))),
            const Text('Este evento es sintético: no registra las acciones realizadas '
              'en esta demostración. La auditoría real será generada por el backend.'),
          ],
        ],
      ))),
    ),
  );
}
