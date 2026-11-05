import 'package:flutter/material.dart';
import '../examen_demo.dart';
import '../detalle_examen_page.dart';
import '../examenes_page.dart';
import 'formulario_examen_page.dart';

/// Conserva los registros únicamente durante esta sesión de demostración.
class PanelRegistroPage extends StatefulWidget {
  const PanelRegistroPage({super.key});
  @override
  State<PanelRegistroPage> createState() => _PanelRegistroPageState();
}
class _PanelRegistroPageState extends State<PanelRegistroPage> {
  final _examenes = List<ExamenDemo>.of(examenesDemo);
  String _busqueda = '';
  bool _historial = false;

  Future<void> _registrar() async {
    final examen = await Navigator.of(context).push<ExamenDemo>(
      MaterialPageRoute<ExamenDemo>(builder: (_) => const FormularioExamenPage()));
    if (!mounted || examen == null) return;
    setState(() { _examenes.add(examen); _busqueda = ''; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Añadido a la demostración local. No se almacenó ningún archivo.')));
  }

  @override
  Widget build(BuildContext context) {
    final lista = _examenes.where((e) =>
      e.nombre.toLowerCase().contains(_busqueda.toLowerCase())).toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
    return Scaffold(
      appBar: AppBar(title: const Text('Vitalia Health · Paciente')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: Center(child: SizedBox(width: 1000, child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_historial ? 'Historial de exámenes' : 'Mis exámenes',
              style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            const Text('Datos sintéticos · registros en memoria · sin sesión real'),
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton.icon(onPressed: _registrar,
                icon: const Icon(Icons.add), label: const Text('Registrar examen demo')),
              OutlinedButton(onPressed: () => setState(() => _historial = !_historial),
                child: Text(_historial ? 'Ver mis exámenes' : 'Ver historial')),
              TextButton(onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ExamenesPage())),
                child: const Text('Consulta anterior con filtros · datos iniciales')),
            ]),
            const SizedBox(height: 20),
            TextFormField(
              // Reinicia el campo al regresar de un registro para mostrar el nuevo elemento.
              key: ValueKey(_examenes.length),
              decoration: const InputDecoration(labelText: 'Buscar por nombre',
                prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: (texto) => setState(() => _busqueda = texto.trim()),
            ),
            const SizedBox(height: 20),
            Text('${lista.length} exámenes · ordenados por fecha'),
            if (lista.isEmpty) const Padding(padding: EdgeInsets.all(24),
              child: Text('Sin resultados para esta búsqueda.')),
            for (final examen in lista) Card(child: ListTile(
              leading: Icon(_historial ? Icons.history : Icons.description_outlined),
              title: Text(examen.nombre),
              subtitle: Text('${examen.tipo} · ${examen.fechaTexto}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DetalleExamenPage(examen: examen))),
            )),
            const SizedBox(height: 20),
            const Text('Selección de archivo y S3 pendientes. La IA todavía no está integrada.'),
          ],
        ))),
      ),
    );
  }
}
