import 'package:flutter/material.dart';
import 'examen_demo.dart';
import 'detalle_examen_page.dart';

/// Consulta local con filtros compartida entre web y móvil.
class ExamenesPage extends StatefulWidget {
  const ExamenesPage({super.key});
  @override
  State<ExamenesPage> createState() => _ExamenesPageState();
}
class _ExamenesPageState extends State<ExamenesPage> {
  int _seccion = 0;
  String _busqueda = '';
  String _tipo = 'Todos';
  DateTimeRange? _periodo;

  List<ExamenDemo> get _visibles {
    final lista = examenesDemo.where((e) =>
      e.nombre.toLowerCase().contains(_busqueda.toLowerCase()) &&
      (_tipo == 'Todos' || e.tipo == _tipo) &&
      (_periodo == null ||
        (!e.fecha.isBefore(_periodo!.start) && !e.fecha.isAfter(_periodo!.end)))
    ).toList();
    lista.sort((a, b) => b.fecha.compareTo(a.fecha));
    return lista;
  }

  Future<void> _elegirPeriodo() async {
    final rango = await showDateRangePicker(
      context: context, firstDate: DateTime(2020),
      lastDate: DateTime(2030), initialDateRange: _periodo,
      helpText: 'Filtrar por fecha del examen',
      saveText: 'Aplicar', cancelText: 'Cancelar',
    );
    if (!mounted || rango == null) return;
    setState(() => _periodo = rango);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vitalia Health · Paciente')),
    body: LayoutBuilder(builder: (context, constraints) {
      final contenido = _contenido();
      if (constraints.maxWidth < 800) return contenido;
      return Row(children: [
        NavigationRail(
          selectedIndex: _seccion,
          onDestinationSelected: (i) => setState(() => _seccion = i),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.folder_outlined), label: Text('Mis exámenes')),
            NavigationRailDestination(icon: Icon(Icons.history), label: Text('Historial')),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: contenido),
      ]);
    }),
    bottomNavigationBar: MediaQuery.sizeOf(context).width < 800 ? NavigationBar(
      selectedIndex: _seccion,
      onDestinationSelected: (i) => setState(() => _seccion = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Mis exámenes'),
        NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
      ],
    ) : null,
  );

  Widget _contenido() {
    final lista = _visibles;
    return SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: Align(alignment: Alignment.topCenter,
        child: SizedBox(width: 1000, child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_seccion == 0 ? 'Mis exámenes' : 'Historial de exámenes',
              style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text('Demostración con datos sintéticos. Sin sesión ni almacenamiento real.'),
            const SizedBox(height: 24),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar examen por nombre',
                prefixIcon: Icon(Icons.search), border: OutlineInputBorder(),
              ),
              onChanged: (texto) => setState(() => _busqueda = texto.trim()),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tipo in ['Todos', 'Laboratorio', 'Imagenología'])
                  ChoiceChip(label: Text(tipo), selected: _tipo == tipo,
                    onSelected: (_) => setState(() => _tipo = tipo)),
                OutlinedButton.icon(onPressed: _elegirPeriodo,
                  icon: const Icon(Icons.date_range), label: const Text('Filtrar fechas')),
                if (_periodo != null)
                  TextButton(onPressed: () => setState(() => _periodo = null),
                    child: const Text('Quitar filtro de fechas')),
              ],
            ),
            if (_periodo != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text('Desde ${_fecha(_periodo!.start)} hasta ${_fecha(_periodo!.end)}')),
            const SizedBox(height: 20),
            Text('${lista.length} exámenes · más recientes primero'),
            const SizedBox(height: 12),
            if (lista.isEmpty) const Card(child: Padding(
              padding: EdgeInsets.all(24), child: Text('No hay exámenes que coincidan con los filtros.'))),
            for (final examen in lista)
              Card(child: ListTile(
                leading: Icon(_seccion == 0 ? Icons.description_outlined : Icons.history),
                title: Text(examen.nombre),
                subtitle: Text('${examen.tipo} · ${examen.fechaTexto}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => DetalleExamenPage(examen: examen))),
              )),
            const SizedBox(height: 16),
            const Text('La carga de archivos y la IA se incorporarán en próximos incrementos.'),
          ],
        )),
      ),
    );
  }
  String _fecha(DateTime fecha) => '${fecha.day}/${fecha.month}/${fecha.year}';
}
