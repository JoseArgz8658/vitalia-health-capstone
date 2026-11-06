import 'package:flutter/material.dart';
import '../examenes/examen_demo.dart';
import '../examenes/detalle_examen_page.dart';

class ProfesionalPage extends StatefulWidget {
  const ProfesionalPage({super.key});
  @override
  State<ProfesionalPage> createState() => _ProfesionalPageState();
}
class _ProfesionalPageState extends State<ProfesionalPage> {
  String _busqueda = '';
  @override
  Widget build(BuildContext context) {
    final pacientes = ['Paciente demo 001', 'Paciente demo 002']
      .where((p) => p.toLowerCase().contains(_busqueda.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Panel profesional')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: Center(child: SizedBox(width: 900, child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Pacientes', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text('Datos sintéticos · autorizaciones pendientes del backend'),
            const SizedBox(height: 24),
            TextField(decoration: const InputDecoration(
              labelText: 'Buscar paciente de demostración',
              border: OutlineInputBorder(), prefixIcon: Icon(Icons.search)),
              onChanged: (valor) => setState(() => _busqueda = valor.trim())),
            const SizedBox(height: 16),
            if (pacientes.isEmpty) const Text('No hay pacientes que coincidan.'),
            for (final paciente in pacientes) Card(child: ListTile(
              leading: const Icon(Icons.person_outline), title: Text(paciente),
              subtitle: const Text('Identidad ficticia'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PacienteProfesionalPage(
                  paciente: paciente,
                  examenes: paciente.endsWith('001') ? examenesDemo : const [],
                ))),
            )),
          ],
        ))),
      ),
    );
  }
}

/// Recibe la colección del paciente; no comparte registros entre pacientes.
class PacienteProfesionalPage extends StatelessWidget {
  const PacienteProfesionalPage({super.key, required this.paciente, required this.examenes});
  final String paciente;
  final List<ExamenDemo> examenes;
  @override
  Widget build(BuildContext context) {
    final lista = List<ExamenDemo>.of(examenes)
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
    return Scaffold(
      appBar: AppBar(title: Text(paciente)),
      body: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: Center(child: SizedBox(width: 900, child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Exámenes e historial',
              style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('Registros ficticios · más recientes primero'),
            const SizedBox(height: 20),
            if (lista.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24),
              child: Text('Este paciente de demostración no tiene exámenes.'))),
            for (final examen in lista) Card(child: ListTile(
              title: Text(examen.nombre),
              subtitle: Text('${examen.tipo} · ${examen.fechaTexto}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DetalleExamenPage(examen: examen))),
            )),
            const SizedBox(height: 20),
            const Text('Revisión de extracción pendiente: todavía no existen resultados '
              'generados por IA para corregir o confirmar.'),
          ],
        ))),
      ),
    );
  }
}
